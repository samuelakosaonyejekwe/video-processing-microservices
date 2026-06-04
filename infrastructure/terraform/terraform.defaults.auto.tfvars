# Helm and optional infrastructure defaults for CI/terraform plan.
# Environment-specific values are merged by generate-terraform-tfvars.sh.

cluster_autoscaler_chart     = "cluster-autoscaler"
cluster_autoscaler_namespace = "kube-system"
cluster_autoscaler_timeout   = 600

aws_load_balancer_controller_name       = "aws-load-balancer-controller"
aws_load_balancer_controller_repository = "https://aws.github.io/eks-charts"
aws_load_balancer_controller_chart      = "aws-load-balancer-controller"
aws_load_balancer_controller_namespace  = "kube-system"

metrics_server_release_name      = "metrics-server"
metrics_server_repository        = "https://kubernetes-sigs.github.io/metrics-server/"
metrics_server_chart             = "metrics-server"
metrics_server_namespace         = "kube-system"
metrics_server_create_namespace  = true
metrics_server_timeout           = 600
metrics_server_wait              = true
metrics_server_cleanup_on_fail   = true
metrics_server_atomic            = true
metrics_server_dependency_update = true

# NOTE: environment-specific values (s3_bucket_name, kubernetes_namespace,
# account/region/domain/ARNs, CIDRs) are intentionally NOT set here. They are
# generated into terraform.tfvars from GitHub Variables by
# scripts/generate-terraform-tfvars.sh. Because *.auto.tfvars loads AFTER
# terraform.tfvars and would override it, hardcoding them here would silently
# shadow the GitHub Variables — so they are kept out of this committed file.

tags = {
  ManagedBy = "Terraform"
}

# EKS endpoint: public access enabled so GitHub Actions runners can reach the API.
# public_access_cidrs is scoped to all IPs since GitHub Actions uses dynamic IPs.
# For stricter control, replace with your VPN/office CIDRs.
endpoint_private_access = true
endpoint_public_access  = true
public_access_cidrs     = ["0.0.0.0/0"]
node_disk_size          = 50
capacity_type           = "ON_DEMAND"
ami_type                = "AL2_x86_64"
max_unavailable         = 1

enable_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

# The live cluster's node group is unmanaged (created out-of-band), so terraform
# must NOT create a parallel managed node group against it. The recreate path
# (start-platform.sh) overrides this with -var=create_managed_node_group=true so a
# fresh cluster still gets its nodes provisioned.
create_managed_node_group = false

# Live cluster exists, so adopt it (read its real role; avoids replacement). The
# recreate path overrides with -var=adopt_existing_cluster=false so a fresh
# rebuild doesn't try to read a destroyed cluster.
adopt_existing_cluster = true
