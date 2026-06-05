# Soft shutdown / restart runbook

How to take the platform down to low-cost mode and bring it back **losslessly and
reliably**. Soft mode scales the EKS node group to 0 and stops the Jenkins EC2 —
it does **not** destroy anything, so all data (PVCs/EBS), every workload and all
NetworkPolicies survive in etcd/EBS and come back as-is.

## Shut down (soft)

```bash
AWS_REGION=eu-central-1 EKS_CLUSTER_NAME=video-processing-cluster \
PROJECT_NAME=video-processing APP_ENV=production \
bash scripts/shutdown-platform.sh        # NO --full
```

This scales the node group to 0 and stops Jenkins. Cost drops to ~$116/mo
(control plane + NAT). Nothing is destroyed; no backups are needed for soft mode.

## Restart (soft) — the smooth, secret-free path

```bash
AWS_REGION=eu-central-1 EKS_CLUSTER_NAME=video-processing-cluster \
PROJECT_NAME=video-processing APP_ENV=production \
EKS_DESIRED_SIZE=3 EKS_MIN_SIZE=1 EKS_MAX_SIZE=3 \
bash scripts/restart-platform-soft.sh
```

It scales the node group back up, starts Jenkins, then runs
`scripts/reconcile-platform.sh` and verifies the endpoints. No deploy secrets are
required, because soft restart re-uses the workloads already in etcd (it does not
re-deploy). Expect ~10 min; data returns to its exact pre-shutdown state.

> Use `scripts/start-platform.sh` (which re-deploys and needs ALL the secrets)
> **only** for a FULL recreate after a `--full` shutdown.

## Why the reconciler exists (the two non-obvious restart hazards)

### 1. Data-AZ capacity (handled automatically)

Every PVC is an EBS volume **locked to one AZ**, and on this cluster all the data
PVCs live in `eu-central-1b`. A stateful pod can only schedule onto a node in its
volume's AZ, and that AZ may need **more than one node** to hold every stateful
pod (postgres + mongo + rabbitmq + redis + grafana + prometheus). The managed
node group's ASG balances across AZs and does **not** guarantee enough nodes land
in `1b`, so on some restarts postgres/rabbitmq got stuck `Pending`
("Insufficient cpu" / "volume node affinity conflict").

`reconcile-platform.sh` fixes this deterministically and safely: it waits until
every stateful pod is scheduled and, if any is `Pending` for a capacity/AZ reason,
scales the node group **up** (bounded by `RECONCILE_MAX_EXTRA_NODES`, default 2)
until they all fit. It only scales up and restarts nothing — it cannot lose data.

If the guard had to add a node (so you end at e.g. 4 instead of 3) and you want
the exact original footprint back, trim a **non-data-AZ** node safely — never let
the ASG pick, or it may drop a `1b` node and strand the data pods:

```bash
ASG=$(aws eks describe-nodegroup --cluster-name "$EKS_CLUSTER_NAME" \
  --nodegroup-name "$NODEGROUP" --region "$AWS_REGION" \
  --query 'nodegroup.resources.autoScalingGroups[0].name' --output text)
kubectl scale deploy cluster-autoscaler-aws-cluster-autoscaler -n kube-system --replicas=0   # pause CA
kubectl cordon "<a-1a-node>" && kubectl drain "<a-1a-node>" --ignore-daemonsets --delete-emptydir-data
# protect the keepers (the 1a node you keep + BOTH 1b nodes) so only the drained 1a node can go:
aws autoscaling set-instance-protection --auto-scaling-group-name "$ASG" --region "$AWS_REGION" \
  --instance-ids <keep-1a-id> <1b-id-1> <1b-id-2> --protected-from-scale-in
aws eks update-nodegroup-config --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$NODEGROUP" \
  --region "$AWS_REGION" --scaling-config "minSize=1,maxSize=3,desiredSize=3"
# then REMOVE protection (critical — else the next soft-shutdown can't scale to 0) and resume CA:
aws autoscaling set-instance-protection --auto-scaling-group-name "$ASG" --region "$AWS_REGION" \
  --instance-ids <keep-1a-id> <1b-id-1> <1b-id-2> --no-protected-from-scale-in
kubectl scale deploy cluster-autoscaler-aws-cluster-autoscaler -n kube-system --replicas=1
```

### 2. Monitoring service discovery (known AWS VPC CNI limitation)

The 4 infrastructure dashboards (Kubernetes / EKS / Node / Pod) need Prometheus to
reach the Kubernetes **API server** for service discovery. That egress is governed
by **AWS VPC CNI Network Policy**, whose agent **unreliably programs egress to the
API server for policy-governed pods after a node recreation**. Symptom: after a
restart Prometheus shows only its ~8 static targets and the 4 infra dashboards are
empty (`dial tcp 172.20.0.1:443: i/o timeout` in the Prometheus log); the 3 app/DB
dashboards and the whole platform are unaffected.

**Do NOT** try to fix this by restarting Prometheus / kube-state-metrics / aws-node
— a fresh pod re-hits the same agent bug and it can make things worse. The agent
also does **not** honour NetworkPolicy exemptions (ipBlock-to-apiserver allows or
pod exclusions), so it cannot be fixed by editing policies.

**Durable fix:** run the monitoring scrapers (Prometheus + kube-state-metrics) in a
namespace **without** a `default-deny-all` policy, so their egress is not subject
to the VPC CNI policy agent at all (policy-free pods reach the API server
reliably, exactly like pods in `kube-system`/`default`). This is a deliberate,
watched change — see the "monitoring namespace move" task. Until then the 4 infra
dashboards are best-effort after a restart (they recover if/when the agent
reconciles); everything else is reliable.

## Verify after any restart

```bash
AWS_REGION=eu-central-1 EKS_CLUSTER_NAME=video-processing-cluster \
bash scripts/reconcile-platform.sh      # safe, idempotent: capacity guard + health report
```

Checklist: 3 nodes Ready (1×1a + 2×1b) · 0 unhealthy pods · postgres/mongo counts
match pre-shutdown · public endpoints (frontend / api / grafana) return 200.
