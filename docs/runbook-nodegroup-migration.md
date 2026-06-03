# Runbook — EKS Node Group Migration (create-before-destroy → t3.large × 3)

**Goal:** bring the EKS worker node group back under clean Terraform management with
**no capacity loss**, by creating a fresh managed node group and retiring the old
unmanaged one. Net result: consistent state, fully IaC-managed, zero permanent debt.

**Why this is needed:** prior interrupted applies left Terraform state inconsistent —
it tracks a *phantom* `production-workers` node group (does not exist in AWS) while the
**real** running node group `default-20260530123759615800000021` (t3.large × 3) is
*unmanaged* (not in state). The running nodes were created with a submodule-managed IAM
role + their own launch template; the config was later refactored to an external node
role, so a straight `import` would force a node replacement anyway. A clean
create-before-destroy migration is therefore the lowest-risk path to a managed, consistent
node group.

**Disruption profile:** ~10–20 min, *rolling* (new nodes Ready before old drain). Pods
reschedule onto new nodes; multi-replica services stay up; any single-replica service
blips briefly during its reschedule. Choose a low-traffic window.

**Pre-set (already done):** GitHub Variables aligned to live capacity —
`EKS_INSTANCE_TYPE=t3.large`, `EKS_DESIRED_SIZE=3`, `EKS_MAX_SIZE=3`, `EKS_MIN_SIZE=1`.

---

## 0. Pre-flight (read-only — abort if anything is off)

```bash
# Cluster + nodes healthy
kubectl get nodes
kubectl get pods -A | grep -vE 'Running|Completed'   # expect only known pre-existing issues
# Confirm the live node group
aws eks list-nodegroups --cluster-name video-processing-cluster --region eu-central-1
# Full state backup (KEEP THIS — rollback anchor)
cd infrastructure/terraform
terraform state pull > /tmp/tfstate-pre-migration.json
terraform plan -lock=false -no-color > /tmp/pre-migration-plan.txt 2>&1   # review before proceeding
```
Proceed only if: nodes Ready, no *new* unhealthy pods, backup written, and you (and I)
have reviewed the plan.

## 1. Reconcile state (state-only ops — AWS untouched; reversible via backup)

```bash
cd infrastructure/terraform
# Remove the phantom production-workers NODE GROUP (confirmed absent in AWS)
terraform state rm 'module.eks.module.eks.module.eks_managed_node_group["production-workers"].aws_eks_node_group.this[0]'
# (Keep the production-workers launch template + IAM role in state for now — they are
#  real orphans; they get cleaned in step 4. Removing the phantom NG is the only state
#  lie that must go before planning.)
# Remove deposed orphan instances if `terraform plan` still references them after refresh.
terraform plan -lock=false -no-color > /tmp/post-rm-plan.txt 2>&1   # MUST show no live resource destroyed
```
**Gate:** the plan must NOT show the running cluster (cluster, RDS, S3, the live default
node group — which is unmanaged and therefore never in any tf destroy) being
destroyed/replaced. If it does → `terraform state push /tmp/tfstate-pre-migration.json`
and STOP.

## 2. Create the NEW managed node group (additive — both groups run together)

Decision on identity: set `EKS_NODE_GROUP_NAME` so the new managed group has a distinct
key from the old AWS group (`default-…`). Recommended: keep `production-workers` so the
new group is clearly the managed one.

```bash
# Generate tfvars from GitHub Variables (t3.large × 3 already set)
infrastructure/terraform/scripts/generate-terraform-tfvars.sh
cd infrastructure/terraform
# Create ONLY the new node group first (targeted, additive)
terraform apply \
  -target='module.eks.module.eks.module.eks_managed_node_group["production-workers"]' \
  -auto-approve
```
Wait for the new nodes to register and be Ready:
```bash
kubectl get nodes -L eks.amazonaws.com/nodegroup -w   # until 3 new production-workers nodes are Ready
```
**Gate:** 3 new nodes Ready; existing pods still Running on old nodes. Now BOTH groups
serve (6 nodes total) — no capacity loss.

## 3. Drain the OLD (unmanaged) node group → pods reschedule onto the new nodes

```bash
# Cordon old nodes
for n in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=default-20260530123759615800000021 -o name); do
  kubectl cordon "$n"
done
# Drain one at a time (respect PDBs; allow emptyDir eviction)
for n in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=default-20260530123759615800000021 -o name); do
  kubectl drain "$n" --ignore-daemonsets --delete-emptydir-data --timeout=300s
  kubectl get pods -A | grep -vE 'Running|Completed'   # verify reschedule health before next node
done
```
**Gate:** after each drain, all app pods Running on the new nodes. If a pod won't
schedule (capacity), `kubectl uncordon` the old nodes and STOP — investigate.

## 4. Retire the OLD node group + clean the orphans

```bash
# Delete the old AWS node group (it is UNMANAGED, so remove it directly)
aws eks delete-nodegroup --cluster-name video-processing-cluster \
  --nodegroup-name default-20260530123759615800000021 --region eu-central-1
aws eks wait nodegroup-deleted --cluster-name video-processing-cluster \
  --nodegroup-name default-20260530123759615800000021 --region eu-central-1
# Clean the orphan IAM role + launch template left by the OLD group (verify unused first)
#   role:  default-eks-node-group-20260530122805519800000016
#   lt:    lt-0024ebcb3877e46bc  (default-2026053012375325260000001f)
# And the failed-apply orphans:
#   role:  production-workers-eks-node-group-20260602162338469900000001
#   lt:    production-workers-20260603024815644800000005
```
Remove any now-orphaned state entries (`terraform state rm` for the old `default` key IAM
artifacts) so state matches reality.

## 5. Final convergence + verification

```bash
cd infrastructure/terraform
terraform plan -lock=false -no-color    # REVIEW: should show only the remaining intended
                                        # hardening (IRSA scoping, etc.), NO node group churn
# If the plan is clean and approved:
terraform apply                          # converges IRSA scoping + any remaining additive items
kubectl get nodes        # 3 production-workers nodes, all Ready
kubectl get pods -A | grep -vE 'Running|Completed'   # only known pre-existing issues
```

## Rollback
- **During steps 1–2** (state ops / new NG creation): `terraform state push
  /tmp/tfstate-pre-migration.json`; if a stray new node group was made, `aws eks
  delete-nodegroup` it. The old node group is untouched → cluster unaffected.
- **During step 3** (draining): `kubectl uncordon` the old nodes; pods reschedule back.
  The old group is still alive until step 4, so this is fully reversible.
- **After step 4** (old group deleted): forward-only — but by then the new group is
  verified healthy before the old is deleted.

## Notes
- IRSA per-service S3 scoping is part of the final convergence (step 5). Before applying,
  confirm each service's required S3 access matches the scoped policy (gateway: uploads
  R/W; converter/worker: input R + output W; auth/notification: none). The thumbnail
  bucket `video-converter-thumbnails-sam` is not Terraform-managed and is unaffected.
- CNI network-policy enforcement is currently OFF (`--enable-network-policy=false`), so
  the deployed NetworkPolicies are inert until enabled; enabling enforcement is a separate,
  deliberate change (verify allow-rules first).
