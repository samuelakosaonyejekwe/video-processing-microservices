# Full-mode shutdown/restore — backup & restore automation

Full-mode shutdown (`scripts/shutdown-platform.sh --full`) destroys the EKS
cluster, the Jenkins EC2, and the NAT gateway to cut cost to ~$10/month. Start
(`scripts/start-platform.sh`) recreates everything. This document describes the
backup/restore automation that makes that cycle **data-preserving**, and — just
as importantly — what it can and cannot guarantee.

## What is preserved across a full destroy+recreate

| Data | Mechanism | Backup point | Restore point |
|---|---|---|---|
| Postgres + MongoDB | logical dump → S3 | shutdown STEP 0 (`dump-databases.sh`) | start STEP 8b (`restore-databases.sh`) |
| RabbitMQ topology | `export_definitions` → S3 | shutdown STEP 0 (`backup-rabbitmq.sh`) | start STEP 8c (`restore-rabbitmq.sh`) |
| RabbitMQ messages | mnesia data dir → S3 | shutdown STEP 0 | start STEP 8c |
| Jenkins home | **EBS snapshot** of the root volume | shutdown STEP 2b (`backup-jenkins.sh`) | start STEP 8e (`restore-jenkins.sh`) |
| Domain → ALB | deterministic Route53 re-point | n/a | start STEP 8d (`repoint-dns.sh`) |
| ECR images, GH secrets/vars, S3 buckets | live outside the cluster | not destroyed | n/a |

Shutdown **aborts the destroy** if the DB, RabbitMQ, or Jenkins backup fails
(override per-component with `SKIP_DB_DUMP` / `SKIP_RABBITMQ_BACKUP` /
`SKIP_JENKINS_BACKUP`). Better to keep paying than to lose data silently.

### Zero-loss coverage for the remaining PVCs (added 2026-06-04)

Every PVC is destroyed in full mode; each is now covered so a restart is data-complete:

| PVC / data | Mechanism | Backup point | Restore point |
|---|---|---|---|
| Grafana hand-built dashboards | API export → S3 (`backup-grafana.sh`) | shutdown STEP 0 | start STEP 8c2 (`restore-grafana.sh`) |
| Redis | RDB snapshot → S3 (`backup-redis.sh`) | shutdown STEP 0 | start STEP 8c2 (`restore-redis.sh`) |
| Prometheus metrics history | TSDB tar → S3 (`backup-prometheus.sh`, best-effort) | shutdown STEP 0 | start STEP 8c2 (`restore-prometheus.sh`) |
| converter scratch (`converter-pvc`) | none needed | — | result re-derived from the queued job + S3 source |

Grafana/Redis/Prometheus backups are **non-fatal** (they `warn` but don't abort the
destroy) — they are recoverable config/cache/observability, not core business data.

### Recreate-path fixes (so the restart actually completes)

The fresh rebuild is gated by two variables (live defaults vs recreate overrides):

- `adopt_existing_cluster` — live `true` (read the running cluster's role); recreate
  `false` (no cluster to read, so the apply doesn't error on the data source).
- `create_managed_node_group` — live `false` (leave the unmanaged node group); recreate `true`.
- `cluster_encryption_kms_key_arn` — live pins the existing key; recreate `""` (fresh key).

`start-platform.sh` passes `-var=adopt_existing_cluster=false -var=create_managed_node_group=true -var=cluster_encryption_kms_key_arn=` on the recreate apply.

## What CANNOT be retained (AWS assigns these at creation)

A full destroy of the EKS control plane necessarily produces **new**:

- **OIDC issuer URL** — start re-applies IRSA against the new provider.
- **EKS API endpoint** — kubeconfig is refreshed automatically.
- **Worker node IPs** — ephemeral; nothing depends on them.
- **ALB DNS name** — a new ALB is created; `repoint-dns.sh` updates Route53 so the
  **domains keep working** (`samuelonyejekwe.com`, `api.`, `grafana.`), even though
  the underlying ALB hostname changes.

If you need any of those identifiers to be stable, do **not** use full mode — use
soft mode (control plane stays up). See `shutdown-platform.sh` header.

## RabbitMQ guarantee (be precise)

- **Topology** (vhosts/exchanges/queues/bindings/users/policies): fully restored
  via `import_definitions`. All project queues are `durable`.
- **Messages**: durable/persistent messages on disk are captured in the mnesia
  snapshot and restored. For a consistent capture, shutdown briefly runs
  `rabbitmqctl stop_app` (`QUIESCE=true`).
- **Not guaranteed**: non-persistent messages, transient queues, and bytes
  in-flight on the wire at the instant of teardown. In practice loss ≈ 0 because
  the app uses a transactional **outbox + job-id idempotency**, so anything missed
  is re-published and de-duplicated.

## Jenkins backup/restore details

- Jenkins runs as a Docker container with `/var/jenkins_home` on the **root EBS
  volume**. Backup = an **EBS snapshot** (`Component=jenkins-backup` tag, newest N
  kept via `JENKINS_BACKUP_RETENTION`). Because full-mode shutdown stops the
  instance first (STEP 2), the snapshot is crash-consistent. No SSH/SSM needed for
  backup.
- Restore (`restore-jenkins.sh`): create a volume from the newest snapshot →
  attach to the recreated instance → copy the `jenkins-data` volume contents in
  **via SSM** → restart Jenkins → detach/delete the temp volume. The recreated
  instance is SSM-managed (the agent is installed in the Jenkins user-data and the
  role has `AmazonSSMManagedInstanceCore`).

### Manual Jenkins restore (fallback)

If `restore-jenkins.sh` cannot reach SSM, it leaves the temp volume attached and
prints these steps:

```sh
# on the Jenkins instance
sudo mkdir -p /mnt/jr && sudo mount /dev/nvme1n1p1 /mnt/jr     # device per `lsblk`
SRC=$(sudo find /mnt/jr/var/lib/docker/volumes -maxdepth 1 -name '*jenkins*' | head -1)/_data
cd /opt/jenkins && docker compose stop jenkins
DEST=$(docker volume inspect "$(docker volume ls -q | grep jenkins | head -1)" -f '{{.Mountpoint}}')
sudo rm -rf "$DEST"/* && sudo cp -a "$SRC"/. "$DEST"/
docker compose up -d && sudo umount /mnt/jr
# then detach + delete the temp volume from the AWS console/CLI
```

## Verification status

Verified non-disruptively against the live cluster:

- `backup-rabbitmq.sh` (online) — definitions + mnesia uploaded to S3; pod healthy after.
- `repoint-dns.sh` — discovered all ingress hosts, synced Route53 to the live ALB (idempotent).
- `backup-jenkins.sh` — EBS snapshot created and completed; instance unaffected.

Code-validated only (exercised end-to-end during a real full cycle):

- `restore-databases.sh`, `restore-rabbitmq.sh`, `restore-jenkins.sh` — running
  these against a live system would overwrite live data, so they are validated by
  syntax/logic + the manual fallback above, and run for real only during start.

## Pre-flight: read-only destroy dry-run

Before a real full shutdown, surface destroy problems without making changes:

```sh
cd infrastructure/terraform
terraform plan -destroy -lock=false -input=false \
  -target=module.eks -target=module.jenkins
```

This refreshes against AWS and prints the destroy plan. Note the terraform state
does not fully match live reality (the running node group is unmanaged), so the
plan reflects **state**, not the live world — interpret accordingly. The live
node group is handled at destroy time by `shutdown-platform.sh` STEP 3b
(AWS-native node-group deletion) regardless of terraform state.
