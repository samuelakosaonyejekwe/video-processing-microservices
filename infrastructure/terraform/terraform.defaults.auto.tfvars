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

s3_bucket_name       = "samuel-video-processing-video"
kubernetes_namespace = "video-processing"

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
