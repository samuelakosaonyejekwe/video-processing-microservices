# Database Backups

The production databases (`mongodb`, `postgresql`) run as in-cluster StatefulSets
on EBS-backed PVCs in the `database` namespace. They are backed up with **AWS
Backup daily EBS snapshots**.

> Set up 2026-06-03 after confirming **no backup mechanism was active** — the
> `scripts/backup-*.sh` logical-dump scripts existed but nothing invoked them,
> no backup bucket/`DATABASE_BACKUP_BUCKET` existed, and no backup CronJob ran.

## What's protected
| DB | PVC | EBS volume | AZ | Size |
|----|-----|------------|----|----|
| MongoDB | `mongodb-pvc` | `vol-01463d4196406ba7c` | eu-central-1b | 10Gi |
| PostgreSQL | `postgresql-data-postgresql-0` | `vol-0326ca52ab1f50a7b` | eu-central-1b | 10Gi |

Both volumes are tagged `Backup=daily` (the backup selection key).

## AWS Backup configuration (region eu-central-1, account 009850210027)
- **Vault:** `video-processing-db-backup-vault` (snapshots encrypted with the
  AWS-managed backup KMS key — note the *source* volumes are currently
  unencrypted at rest; the snapshots in the vault are encrypted).
- **Plan:** `video-processing-db-daily` (id `b13ebd37-7702-42b2-93f0-34f5b43e3031`)
  - Rule `daily-30d`: `cron(0 3 * * ? *)` (daily 03:00 UTC), start window 60m,
    completion window 180m, **retention 30 days**.
- **Selection:** `db-volumes` — resources tagged `Backup=daily`, via role
  `video-processing-aws-backup-role` (managed policies
  `AWSBackupServiceRolePolicyForBackup` + `...ForRestores`).

These are **AWS-native, not terraform-managed** (consistent with the decision to
keep the EKS cluster out of terraform — see
`eks-terraform-state-rebuild-runbook.md`). EBS snapshots are **crash-consistent**
(no quiescing); single-node Mongo/Postgres recover cleanly from crash-consistent
state via journal/WAL on restore.

## Restore (DR)
1. Find a recovery point:
   ```bash
   aws backup list-recovery-points-by-backup-vault \
     --backup-vault-name video-processing-db-backup-vault --region eu-central-1
   ```
2. Restore the snapshot to a new EBS volume (same AZ as the node that will mount it):
   ```bash
   aws backup start-restore-job --region eu-central-1 \
     --recovery-point-arn <arn> \
     --iam-role-arn arn:aws:iam::009850210027:role/video-processing-aws-backup-role \
     --metadata '{"volumeType":"gp3","availabilityZone":"eu-central-1b"}'
   ```
3. Bind the restored volume to a new PV/PVC and point the StatefulSet at it
   (scale the StatefulSet to 0, swap the PVC's volume, scale back up), or
   provision a fresh DB and migrate.

## Verify backups are running
```bash
aws backup list-backup-jobs --region eu-central-1 \
  --by-backup-vault-name video-processing-db-backup-vault \
  --query 'BackupJobs[].{r:ResourceArn,state:State,created:CreationDate}' --output table
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name video-processing-db-backup-vault --region eu-central-1 \
  --query 'RecoveryPoints[].{arn:RecoveryPointArn,status:Status,size:BackupSizeInBytes}' --output table
```

## Follow-ups / notes
- **Source volumes are unencrypted at rest** (`Encrypted=False`). The snapshots
  are encrypted, but encrypting the live volumes would require recreating them
  (migrate to an encrypted gp3 volume) — deferred, defense-in-depth.
- `scripts/backup-postgres.sh` / `backup-mongodb.sh` are an **alternative**
  logical-dump approach (pg_dump/mongodump → S3) for granular/table-level
  restore. They are **not currently wired** to any schedule; EBS snapshots are
  the active mechanism. Wire them as CronJobs only if logical restore is needed
  (they'd need a backup S3 bucket, IRSA, and — under NetworkPolicy enforcement —
  an egress policy for the backup pod to reach the DBs).
- Consider periodically running a **restore test** to validate recoverability.
