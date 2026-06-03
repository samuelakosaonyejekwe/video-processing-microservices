# Database Backups

The production databases (`mongodb`, `postgresql`) run as in-cluster StatefulSets
on EBS-backed PVCs in the `database` namespace. There are **two** backup
mechanisms:

1. **AWS Backup daily EBS snapshots** (scheduled DR — see below).
2. **Logical dump→S3 on full shutdown, restore on start** (so a full
   destroy+recreate loses NO data — see "Full-mode shutdown/restore" below).

## Full-mode shutdown/restore (no data loss across a destroy+recreate)
`scripts/dump-databases.sh` and `scripts/restore-databases.sh` do `pg_dump` /
`mongodump` (and the reverse) **inside the DB pods via `kubectl exec`**, streaming
to/from **`s3://samuel-video-processing-db-dumps`** (`DATABASE_BACKUP_BUCKET`,
private + versioned + AES256 + 30-day lifecycle). No extra images, IRSA, or
NetworkPolicies are needed.

- **Full shutdown** (`shutdown-platform.sh --full`) runs `dump-databases.sh`
  FIRST (STEP 0, while the DBs are still up) and **aborts the destroy if the
  dump fails** (so data is never lost silently). `SKIP_DB_DUMP=true` overrides.
- **Start** (`start-platform.sh`) runs `restore-databases.sh` after services
  deploy (STEP 8b), restoring the latest dump (idempotent: `--clean`/`--drop`),
  then restarts the app deployments. `RESTORE_DATABASES=false` skips (fresh start).
- **Verified** 2026-06-03: dump→restore round-trip into scratch DBs reproduced
  exact row/doc counts (postgres users, mongo conversion_jobs).

So: **soft shutdown** = nothing lost, ~$116/mo remaining; **full shutdown** =
~$10/mo AND nothing lost (DBs dumped to S3 and restored on start). A full
destroy+recreate also rebuilds the EKS cluster fresh, which **resolves the
terraform state drift** as a side effect.

## AWS Backup daily EBS snapshots

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
- **Vault:** `video-processing-db-backup-vault`. NOTE: EBS snapshots **inherit
  the source volume's encryption state**, and the source volumes are currently
  **unencrypted**, so the recovery points are **unencrypted** (the vault KMS key
  does not force-encrypt EBS snapshots of unencrypted sources). See follow-ups
  to get encrypted backups.
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
- **Source volumes are unencrypted at rest** (`Encrypted=False`), so the
  recovery points are also unencrypted. To get **encrypted backups**, either
  (a) migrate the live volumes to encrypted gp3 (recreates the PVCs — disruptive,
  the more thorough fix), or (b) add an AWS Backup **copy action** to a
  CMK-encrypted vault, which re-encrypts on copy. Deferred — defense-in-depth;
  the backups exist and are restorable today.
- `scripts/backup-postgres.sh` / `backup-mongodb.sh` are an **alternative**
  logical-dump approach (pg_dump/mongodump → S3) for granular/table-level
  restore. They are **not currently wired** to any schedule; EBS snapshots are
  the active mechanism. Wire them as CronJobs only if logical restore is needed
  (they'd need a backup S3 bucket, IRSA, and — under NetworkPolicy enforcement —
  an egress policy for the backup pod to reach the DBs).
- Consider periodically running a **restore test** to validate recoverability.
