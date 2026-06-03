# Security Hardening — Comprehensive Audit & Remediation

A full-system security audit was performed across six domains (application code,
Terraform/IAM, Kubernetes, CI/CD, shell scripts, container/config). This document
records what was found and fixed, and the manual follow-ups required to complete
the hardening.

## Application code (Python)

- **Token-type confusion (CRITICAL):** the gateway accepted JWTs with no `type`
  claim as access tokens. Now requires `type == "access"` explicitly in
  `gateway/middleware/auth_middleware.py`, `gateway/main.py`, and
  `shared/security/ws_auth.py`.
- **HS-path skipped `iss`/`aud` (CRITICAL):** JWT verification now always enforces
  issuer and audience (and `verify_aud=True`) regardless of algorithm family.
- **CORS + credentials (HIGH):** auth and converter now set
  `allow_credentials = (origins != ["*"])` and reject `"*"` origins at startup,
  matching the gateway.
- **Converter JWT algorithm (HIGH):** algorithm is uppercased, validated against the
  shared allow-list, and required to be RS* (prevents RS/HS confusion).
- **Path traversal (HIGH):** hardened `converter/ffmpeg/convert.py` (output path
  containment + `-y`) and `converter/storage/local_storage.py` (sanitized,
  base-dir-confined writes).
- **Fail-open revocation (MEDIUM):** the auth service now hard-fails at startup in
  production if `REDIS_HOST` is unset (token revocation must not silently no-op).
- **SMTP subject header injection (MEDIUM):** CR/LF rejected in email subject.
- **WebSocket origin (MEDIUM):** missing `Origin` no longer auto-allowed; the
  server-to-server exemption is gated behind `WS_ALLOW_MISSING_ORIGIN` (default off).

## Kubernetes

- `automountServiceAccountToken: false` on all service accounts + the migration job.
- Default-deny NetworkPolicies (with DNS egress) extended to the database,
  messaging, monitoring, and tracing namespaces; egress added to the DB/redis
  policies.
- RabbitMQ policy scoped to specific producer/consumer pods; the management port is
  restricted to pods labelled `rabbitmq-management-access: "true"`.
- Resource requests/limits added to the migration, cleanup, and index jobs.
- `LimitRange` backstop added (`policies/limit-range.yaml`, wired into
  `deploy-services.sh`). A `ResourceQuota` is intentionally left disabled until peak
  capacity is measured (would otherwise risk rejecting HPA/KEDA scale-out pods).
- Pod Security Standards `restricted` enforced on the app namespace.

## CI/CD

- `deploy-eks-services.yml` deploy job gated behind a GitHub `production`
  Environment + `if: always()` secret-file cleanup.
- OIDC support added to all AWS workflows (opt-in via `vars.AWS_OIDC_ROLE_ARN`),
  static keys retained as fallback.
- All third-party actions SHA-pinned.
- Script-injection sinks removed (inputs/vars/secrets moved out of `run:`
  interpolation into `env:`).
- gitleaks now fails the build on findings; `ci.yml` reduced to least-privilege
  `contents: read`.
- `database-validation.yml` now actually validates SQL/JS; deploy readiness check
  no longer reports failed deploys as green.

## Shell scripts

- JWT private key written `chmod 600`; runtime env file created `umask 077`.
- Destructive ops (`destroy-cluster.sh`, `shutdown-platform.sh --full`) gated behind
  a shared `confirm-destructive.sh` guard (`CONFIRM_DESTROY=yes` / `--yes` for CI).
- mongo `--eval` injection closed (database/auth-source allow-listed).
- Registry passwords no longer passed on the kubectl command line.
- Production fail-closed defaults (Erlang cookie, CORS, Grafana creds).
- Backups uploaded with SSE; `set -euo pipefail` added to standalone scripts.

## Container / config

- Production RabbitMQ (Kubernetes/Helm, `definitions.json`) defines **no** users —
  credentials come from Secrets — and its management port is locked down by
  NetworkPolicy. The local docker-compose broker intentionally keeps the built-in
  `guest` user (it is bound to 127.0.0.1 and is dev/integration-only).
- Helm postgres password is now `required` (no `postgres/postgres` default).
- docker-compose secrets are fail-closed (`${VAR:?...}`).
- nginx: `server_tokens off`, security headers, `/api/` rate limiting, runs non-root.
- Postgres: least-privilege grants (no `ALL ON DATABASE`); indexes + CHECK
  constraints added.

## Terraform / IAM

- IRSA trust policies now bind the `:aud` claim; S3 access scoped per-service
  (auth/notification lose S3 entirely; converter/worker lose cross-bucket Delete).
- EKS secrets envelope encryption: kept (it is already enabled on the live
  cluster via the EKS module's own KMS key). The earlier attempt to swap it to a
  separate CMK was reverted because, on the live cluster, it forced Terraform to
  destroy the in-use cluster KMS key — a dangerous, outage-prone change. Node EBS
  encryption + IMDSv2 enforcement were likewise reverted from the EKS module
  because they force a rolling node replacement; defer them to a deliberate
  maintenance window rather than an unattended apply.
- VPC Flow Logs + multi-region CloudTrail added (KMS-encrypted).
- Terraform state backend bootstrap hardened (public-access-block, KMS, TLS-only).
- ECR KMS encryption; `force_delete` made configurable (default false).
- Jenkins instance profile ECR access scoped to project repos.
- Removed the dead, hardcoded `s3-policy.json` (account ID + bucket names baked
  in); its policy is managed by Terraform. GitHub Actions policy S3 ARNs
  templated to `${AWS_S3_*_BUCKET}` placeholders (no committed literals).
- `endpoint_private_access = true` added (public access kept, per decision).
- Separate `jenkins_allowed_cidr_blocks` var so the Jenkins UI can be scoped off
  `0.0.0.0/0` without affecting EKS.

---

## ⚠️ Manual follow-ups required

These complete the hardening but need access/decisions outside this change:

1. **Create the GitHub `production` Environment** (Settings → Environments) with
   required reviewers, and move the production secrets into it — otherwise the new
   `environment: production` gate does not enforce approval.
2. **Create the GitHub OIDC IAM role** (set `enable_github_oidc = true` in Terraform,
   then set repo var `AWS_OIDC_ROLE_ARN`) to retire static AWS keys.
3. **Narrow `jenkins_allowed_cidr_blocks`** in `terraform.tfvars` to your admin/VPN
   IP (currently defaults to the existing broad value to avoid lock-out).
4. **Review the `0.0.0.0/0` `public_access_cidrs`** — kept public because CI relies
   on it; narrow once OIDC + private runners are in place.

## ⚠️ Apply-time impact on live infrastructure

A read-only `terraform plan` against the live cluster was used to verify blast
radius. The dangerous EKS-module changes (KMS-key swap, node EBS/IMDSv2) have been
reverted so an apply no longer destroys the in-use cluster KMS key or replaces
nodes. Remaining notes:

- ECR CMK encryption is now **non-destructive** for existing repos
  (`lifecycle.ignore_changes`); only new repos get the CMK.
- The auth and converter services now **refuse to start** if `CORS_ALLOWED_ORIGINS`
  is `"*"`; ensure explicit origins are configured before deploying.
- The Terraform **state is mid-way through a previously interrupted apply** (many
  `deposed` objects) and a pending **node-group rename** (`default` →
  `production-workers`). This must be reconciled in a **maintenance window with the
  plan reviewed**, NOT via an unattended apply. Node IMDSv2/EBS encryption should
  be re-introduced as a deliberate, watched change at that time.
