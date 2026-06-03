# EKS Terraform State Rebuild Runbook (Option 2)

**Status:** READY FOR REVIEW — do **not** execute outside a planned maintenance window.
**Author context:** Produced 2026-06-03 after a watched node-group reconciliation found the
terraform state diverged from the live EKS cluster on *immutable* attributes.
**Estimated window:** 2–4 hours (longer if the node-group migration sub-option is chosen).
**Blast radius if done wrong:** total, irreversible loss of the production EKS cluster.

---

## 0. Why this runbook exists (the diagnosis)

The live EKS cluster (`video-processing-cluster`, eu-central-1) is **healthy and
self-consistent**, but the terraform state describes a *partially-applied 2026-06-02 rebuild
attempt*. The live cluster + node group are the **2026-05-30** build, much of which is
**unmanaged** (not in state). A plain `terraform apply` plans **19 add / 13 change / 23 destroy
(+28 deposed)** and, critically, would attempt changes that **force EKS cluster replacement**.

### What actually matches live (good — leave alone)
| Thing | Live value | In state? |
|---|---|---|
| Cluster name / version | `video-processing-cluster` / `1.31` | ✅ matches |
| Cluster IAM role | `video-processing-cluster-cluster-2026053012274644520000000d` (`...0d`) | ✅ recorded (via `data.aws_eks_cluster.existing`) |
| Cluster secrets-encryption KMS key | `2e99c142-566d-4f3f-a930-e456704aa00b` | ✅ recorded on the cluster resource |
| OIDC provider | `...oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/399430FEACFA005DF1764725165CE0B3` | ✅ matches |
| Additional cluster SG | `sg-016f322dedcc004b0` | ✅ matches (`aws_security_group.cluster[0]`) |
| EKS-managed primary cluster SG | `sg-00233b014b59ffd57` | (auto; not module-managed) |

### What diverges (the danger — fix these)
| # | Divergence | Why dangerous | Fix |
|---|---|---|---|
| D1 | Module wants cluster `encryption_config` key = `673c2692-…` (an **orphan** KMS key the module created); live = `2e99c142-…` | `encryption_config` is **IMMUTABLE** → apply forces **cluster REPLACEMENT** | Pin module to the **existing** key `2e99c142`; stop managing the orphan key |
| D2 | State has orphan module-internal cluster role `…cluster-2026060211…0e` (plan: destroy) | Harmless destroy, but noisy | `state rm` |
| D3 | State node-group key `["default"]` holds only orphan node role `default-…2026060211…019` + attachments (plan: destroy) | Harmless destroy of an orphan, but noisy | `state rm` |
| D4 | Live node group `default-20260530123759615800000021` (role `…016`, LT `lt-0024ebcb3877e46bc`) is **unmanaged** | Config wants a *different* node group key `production-workers` → plan wants to CREATE one | See Phase E (decision) |
| D5 | Addons `vpc-cni` / `coredns` / `kube-proxy` are "to create" but exist live | Apply would conflict (`ResourceInUseException`) | `import` each |
| D6 | 28 **deposed** objects (SG rules, attachments) from the interrupted apply | Destroying deposed objects that may still be live SG rules | Inspect each; `state rm` deposed entries that map to live, in-use resources |
| D7 | Peripheral: IRSA managed policies, ECR KMS key/alias, `jenkins_ecr` policy "to create" | Benign creates, but only safe AFTER the EKS module is clean | Phase F via `-target` |

---

## 1. ABSOLUTE SAFETY RULES (read before touching anything)

1. **Never** run `terraform apply` without first running `terraform plan` and reading it in full.
2. **Never** use `-auto-approve` in this runbook.
3. **ABORT IMMEDIATELY** (do not type `yes`) if any plan shows **any** of:
   - `aws_eks_cluster.this[0]` **destroyed** or **must be replaced**, or any change under its
     `encryption_config` block;
   - the live node group `…default-20260530123759615800000021` **destroyed** (a *new* one being
     created is expected in Phase E option E2; the **existing** one being destroyed is not, until
     you have deliberately migrated);
   - `aws_iam_openid_connect_provider.oidc_provider[0]` **destroyed/replaced** (breaks all IRSA);
   - the live node role `default-…016` or live cluster role `…0d` **destroyed**.
4. Work **one change at a time**, re-`plan` after **every** state operation.
5. Keep a **break-glass** path to the cluster that does **not** depend on terraform
   (kubectl with the current kubeconfig; an AWS console session with EKS admin).
6. If anything is ambiguous, **stop and fall back to Option 1** (leave EKS unmanaged — see §9).
   Option 1 is always the safe exit.
7. The S3 backend (`samuel-video-processing-tf-state`) is versioned and DynamoDB-locked
   (`terraform-state-lock`). Every state write creates a new version → recoverable.

---

## 2. Pre-flight checklist

- [ ] Announce a maintenance window. Pause CI: ensure no `terraform-eks.yml` / `deploy-eks-services.yml`
      run can fire mid-rebuild (they take the same state lock). Consider temporarily disabling those
      workflows or running during a quiet period.
- [ ] Confirm `kubectl` works and note current health as a baseline:
      ```bash
      kubectl get nodes
      kubectl get pods -A | grep -ivE 'Running|Completed' || echo "all healthy"
      aws eks describe-cluster --name video-processing-cluster --region eu-central-1 --query 'cluster.status'
      curl -s -o /dev/null -w '%{http_code}\n' https://api.samuelonyejekwe.com/health
      ```
- [ ] Generate correct tfvars (the committed file is stale; this is gitignored):
      ```bash
      cd infrastructure/terraform
      eval "$(gh variable list --json name,value | python3 -c "import sys,json,shlex;[print('export %s=%s'%(x['name'],shlex.quote(x['value']))) for x in json.load(sys.stdin)]")"
      mv ../../.env ../../.env.bak    # .env has an EKS_CLUSTER_NAME placeholder that contaminates
      export JENKINS_INSTANCE_TYPE="${JENKINS_INSTANCE_TYPE:-t3.medium}"
      bash scripts/generate-terraform-tfvars.sh
      mv ../../.env.bak ../../.env
      ```
- [ ] `terraform init` (backend already configured); confirm no pending init drift.

---

## 3. Phase A — Backups & baseline (read-only)

```bash
cd infrastructure/terraform
mkdir -p /tmp/tfstate-backup
STAMP=$(date +%Y%m%d-%H%M%S)
terraform state pull > /tmp/tfstate-backup/rebuild-${STAMP}.tfstate
# Also note the S3 object version id as a second backup:
aws s3api list-object-versions --bucket samuel-video-processing-tf-state \
  --prefix video-processing/production/terraform.tfstate \
  --query 'Versions[0].{VersionId:VersionId,LastModified:LastModified}' --region eu-central-1
# Snapshot the full plan for reference (read-only, lock-free):
terraform plan -lock=false -no-color > /tmp/tfstate-backup/plan-before-${STAMP}.txt 2>&1
grep -E '^Plan:' /tmp/tfstate-backup/plan-before-${STAMP}.txt
```
**Gate:** Save both backups before proceeding. Record the `Plan:` line.

---

## 4. Phase B — Eliminate the cluster-replacement risk (D1) FIRST

This is the single most important phase: until the plan no longer touches the cluster's
`encryption_config`, **nothing else is safe**.

### B.1 Config change — pin the cluster to the EXISTING KMS key
Edit `infrastructure/terraform/modules/eks/main.tf`, in the upstream `module "eks"` block, so the
module **stops creating its own KMS key** and uses the live one:

```hcl
  # Use the cluster's EXISTING secrets-encryption key (immutable; created with
  # the 2026-05-30 cluster). Do NOT let the module create a new key — that would
  # force cluster replacement.
  create_kms_key = false
  cluster_encryption_config = {
    provider_key_arn = "arn:aws:kms:eu-central-1:009850210027:key/2e99c142-566d-4f3f-a930-e456704aa00b"
    resources        = ["secrets"]
  }
```
> ⚠️ Verify the exact variable names against terraform-aws-modules/eks **~> 20.31** (the
> `.terraform/modules/eks.eks` source). In v20 these are `create_kms_key` and
> `cluster_encryption_config`. If the module exposes `kms_key_*` passthroughs, set them to keep the
> existing key and disable key creation. The goal: **module desired encryption == live (2e99c142)**.

### B.2 Remove the orphan KMS key resource from state
The module currently tracks the orphan key `673c2692`. After B.1 the config no longer references it.
```bash
terraform state show 'module.eks.module.eks.module.kms.aws_kms_key.this[0]'   # confirm it is 673c2692 (orphan)
terraform state rm 'module.eks.module.eks.module.kms.aws_kms_key.this[0]'
terraform state rm 'module.eks.module.eks.module.kms.aws_kms_alias.this["cluster"]'
# (Leave the orphan key in AWS for now — deleting a KMS key is a scheduled, reversible-within-window
#  operation; do it separately AFTER the rebuild is verified, never during.)
```

### B.3 GATE — re-plan and verify the cluster is no longer touched
```bash
terraform plan -lock=false -no-color | tee /tmp/tfstate-backup/plan-afterB-${STAMP}.txt | \
  grep -E 'aws_eks_cluster|encryption_config|will be destroyed|must be replaced|^Plan:'
```
**Do not continue** unless the plan shows **NO** change to `aws_eks_cluster.this[0]`’s
`encryption_config` and **no** cluster destroy/replace. If it still wants to change encryption,
STOP — the config in B.1 is not yet correct. Iterate B.1 only.

---

## 5. Phase C — Remove orphan roles & deposed cruft (D2, D3, D6)

Only after Phase B is clean. Each `state rm` is state-only (no AWS change); the orphan AWS roles
can be deleted from AWS afterward.

```bash
# D2: orphan module-internal cluster role (…0e) + its attachments
terraform state show 'module.eks.module.eks.aws_iam_role.this[0]'   # confirm name ends ...2026060211...0e
terraform state rm 'module.eks.module.eks.aws_iam_role.this[0]'
terraform state rm 'module.eks.module.eks.aws_iam_role_policy_attachment.this["AmazonEKSClusterPolicy"]'
terraform state rm 'module.eks.module.eks.aws_iam_role_policy_attachment.this["AmazonEKSVPCResourceController"]'

# D3: orphan node role under the "default" key (…019) + attachments
terraform state show 'module.eks.module.eks.module.eks_managed_node_group["default"].aws_iam_role.this[0]'  # confirm ...019 orphan
terraform state rm 'module.eks.module.eks.module.eks_managed_node_group["default"]'   # removes the whole orphan submodule
```

**D6 — deposed objects (handle with care):** list them and inspect each before removing.
```bash
terraform state pull | python3 - <<'PY'
import json,sys
d=json.load(sys.stdin)
for r in d["resources"]:
    for i in r.get("instances",[]):
        if i.get("deposed"):
            a=i.get("attributes",{})
            print(r.get("module",""), r["type"]+"."+r["name"], "->", a.get("id") or a.get("arn"))
PY
```
For **each** deposed entry: confirm with the AWS CLI whether that physical id (SG rule, attachment)
**still exists and is in use by the LIVE cluster/nodes**.
- If it is an **old, replaced** object that no longer exists in AWS → `terraform state rm '<addr>'`
  (note: deposed addresses need the `-dry-run`-checked exact address; use
  `terraform state rm <addr>` — terraform removes the deposed instance).
- If a deposed object **maps to a live, in-use** SG rule → **do not remove blindly**; leave it and
  reconcile via import in Phase G, or ABORT to Option 1.

**GATE:** re-`plan`. Destroy count should now be limited to genuinely-orphan items. Cluster, OIDC,
live node role must NOT be in the destroy set.

---

## 6. Phase D — Import the existing addons (D5)

The addons exist live; import them so terraform adopts (not recreates) them.
```bash
terraform import 'module.eks.module.eks.aws_eks_addon.this["vpc-cni"]'    'video-processing-cluster:vpc-cni'
terraform import 'module.eks.module.eks.aws_eks_addon.this["coredns"]'    'video-processing-cluster:coredns'
terraform import 'module.eks.module.eks.aws_eks_addon.this["kube-proxy"]' 'video-processing-cluster:kube-proxy'
```
Live versions for reference (the module uses `most_recent = true`, so a benign in-place version/config
update may appear — acceptable, applied in Phase G):
- vpc-cni `v1.20.5-eksbuild.1` (configured `enableNetworkPolicy=true` — keep it)
- coredns `v1.11.4-eksbuild.33`
- kube-proxy `v1.31.14-eksbuild.9`

**GATE:** re-`plan`. Addons should now show *in-place* changes at most (never destroy/replace). The
vpc-cni plan must still carry `enableNetworkPolicy=true` (network-policy enforcement is live).

---

## 7. Phase E — The node group decision (D4)

The live node group `default-20260530123759615800000021` is unmanaged; its name was generated under
the key `"default"`, while config wants key `var.eks_node_group_name = "production-workers"`. EKS
node-group names are immutable, so you **cannot** rename it. Choose ONE:

### Option E1 — Leave the node group UNMANAGED (lowest risk, recommended unless node hardening is required)
- Set the module so it does **not** define a managed node group it will try to create. Either set
  `eks_managed_node_groups = {}` in `modules/eks/main.tf`, or guard the map so no node group is
  rendered. This makes terraform manage the cluster/addons/OIDC/SGs but treat the running nodes as
  external (status quo for the nodes).
- **GATE:** `plan` must show **no** node-group create and **no** destroy of the live node group.
- Trade-off: IMDSv2/EBS node hardening stays deferred; node scaling still works (it is an
  AWS-managed node group, just not in terraform).

### Option E2 — Create-before-destroy migration to a managed node group (gets full management + IMDSv2/EBS, but recreates nodes)
Only in the window, with node disruption accepted. After Phases B–D are clean:
1. In `modules/eks/main.tf` add the new node group definition with hardening:
   ```hcl
   # in eks_managed_node_groups (key = production-workers)
   create_before_destroy = true
   metadata_options = { http_tokens = "required", http_put_response_hop_limit = 1, http_endpoint = "enabled" }
   block_device_mappings = {
     xvda = { device_name = "/dev/xvda", ebs = { volume_size = 50, volume_type = "gp3", encrypted = true, delete_on_termination = true } }
   }
   iam_role_arn = var.node_role_arn   # external; ensure module.iam.node_role has worker+CNI+ECR+EBS policies
   ```
2. `terraform plan` — expect: **create** new `production-workers` node group (+ its LT/role wiring),
   **no** change to cluster/addons/OIDC, **no** destroy of the live `default-2026…` group.
   **ABORT** if the plan destroys the live node group or touches the cluster.
3. `terraform apply` (review, type `yes`). New nodes (t3.large ×3) join.
4. Verify new nodes Ready and workloads schedulable:
   ```bash
   kubectl get nodes -L eks.amazonaws.com/nodegroup
   ```
5. **Cordon & drain** the old nodes so pods move to the new group (respect PodDisruptionBudgets):
   ```bash
   for n in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=default-20260530123759615800000021 -o name); do
     kubectl cordon "$n"; done
   for n in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=default-20260530123759615800000021 -o name); do
     kubectl drain "$n" --ignore-daemonsets --delete-emptydir-data --timeout=10m; done
   ```
   Verify all pods Running on new nodes; verify `https://api.samuelonyejekwe.com/health == 200` and a
   full upload→convert→S3 e2e (`tests/e2e/test_video_conversion_flow.py::test_video_upload_flow`).
6. **Retire** the old unmanaged node group (it is NOT in terraform, so delete via AWS):
   ```bash
   aws eks delete-nodegroup --cluster-name video-processing-cluster \
     --nodegroup-name default-20260530123759615800000021 --region eu-central-1
   aws eks wait nodegroup-deleted --cluster-name video-processing-cluster \
     --nodegroup-name default-20260530123759615800000021 --region eu-central-1
   ```
7. After deletion, clean the now-unused old node role `default-…016` and LT `lt-0024ebcb3877e46bc`
   from AWS (only once nothing references them).

> Recommendation: choose **E1** unless IMDSv2/EBS node hardening is a hard requirement this window.
> E1 fully removes the apply danger with zero node disruption; E2 can be done later as its own
> small, well-scoped change once the cluster state is clean.

---

## 8. Phase F — Peripheral resources (D7), then final verification

Only after the EKS module plan is clean (no destroy/replace of cluster, OIDC, addons, live nodes):

```bash
# IRSA managed policies + attachments (roles already imported earlier this project)
terraform plan -lock=false \
  -target='aws_iam_policy.irsa_s3_gateway' -target='aws_iam_policy.irsa_s3_converter' \
  -target='aws_iam_role_policy_attachment.irsa_s3_gateway' -target='aws_iam_role_policy_attachment.irsa_s3_converter' \
  -target='aws_iam_role.irsa_roles'
# Review: should be CREATE 2 policies + 3 attachments, in-place role tag/trust only. Then apply the same -targets.
```
> Note: the IRSA roles currently also carry working **inline** policies (`gateway-s3`, `converter-s3`,
> `worker-s3`). After the managed policies attach and an upload e2e passes, optionally remove the
> redundant inline policies via `aws iam delete-role-policy` (verify perms are identical first).

ECR KMS key/alias and `jenkins_ecr` policy are benign creates — apply via `-target` similarly, or in
the final full apply once the plan is fully understood.

### Phase G — converge to zero-diff
Re-run `terraform plan`. Iterate config (versions, tags, log types — the live cluster has only
`api,audit` enabled; config adds `authenticator,controllerManager,scheduler`, which is a benign
in-place add you may apply) until:
```
No changes. Your infrastructure matches the configuration.
```
Apply the remaining benign in-place changes deliberately, reviewing each. **Done.**

---

## 9. Rollback / fallback to Option 1 (always available)

At any point, to **abort safely**:
- Restore state from the Phase A backup:
  ```bash
  terraform state push /tmp/tfstate-backup/rebuild-${STAMP}.tfstate   # or restore the S3 version id
  ```
- Or restore the S3 object version recorded in Phase A.
- Then **fall back to Option 1 — leave EKS unmanaged**: `terraform state rm` the entire `module.eks`
  subtree so terraform no longer tracks the cluster at all (it keeps running, unmanaged). This is the
  guaranteed-safe end state; the cluster is never at risk from an accidental apply because terraform
  no longer knows about it.

The running cluster is **never** modified by any rollback step — all rollbacks are state-only.

---

## 10. Appendix — resource inventory (verified 2026-06-03)

**Live (ground truth):**
- Cluster: `video-processing-cluster`, v1.31, role `video-processing-cluster-cluster-2026053012274644520000000d`,
  enc key `2e99c142-566d-4f3f-a930-e456704aa00b`, primary SG `sg-00233b014b59ffd57`, additional SG `sg-016f322dedcc004b0`,
  OIDC id `399430FEACFA005DF1764725165CE0B3`.
- Node group: `default-20260530123759615800000021`, role `default-eks-node-group-20260530122805519800000016`,
  LT `lt-0024ebcb3877e46bc` (name `default-2026053012375325260000001f` v2), t3.large, min1/max3/desired3, AL2_x86_64, ON_DEMAND.
- Addons: vpc-cni `v1.20.5-eksbuild.1` (+enableNetworkPolicy), coredns `v1.11.4-eksbuild.33`, kube-proxy `v1.31.14-eksbuild.9`, plus aws-ebs-csi-driver.

**Orphans (created 2026-06-02, safe to retire after rebuild):**
- KMS key `673c2692-33b3-4835-86fb-15f08f1a60e9` (module.kms in state; NOT used by live cluster).
- IAM roles: cluster `…cluster-2026060211114392180000000e`, node `default-eks-node-group-20260602111202517200000019`.
- (Already removed this project: phantom node group `production-workers-20260603024821…`, orphan role
  `…2026060216233846990000…01`, orphan LT `lt-08650bb00e35c3f4e`.)

**Import ID formats:**
- `aws_eks_addon` → `<cluster>:<addon>` e.g. `video-processing-cluster:vpc-cni`
- `aws_eks_node_group` → `<cluster>:<nodegroup>`
- `aws_iam_role` → role name; `aws_iam_policy` → policy ARN
- `aws_security_group` → `sg-…`; `aws_iam_openid_connect_provider` → provider ARN
- `aws_kms_key` → key id; `aws_launch_template` → `lt-…`

**Backups from the 2026-06-03 session:** `/tmp/tfstate-backup/` (ephemeral — re-pull before starting).
State serial at end of session: **59** (phantom + orphans removed, 5 IRSA roles imported).
