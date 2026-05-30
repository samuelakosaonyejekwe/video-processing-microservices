resource "helm_release" "cluster_autoscaler" {

  name = var.cluster_autoscaler_release_name

  repository = var.cluster_autoscaler_repository

  chart = var.cluster_autoscaler_chart

  namespace = var.cluster_autoscaler_namespace

  create_namespace = false

  cleanup_on_fail = true

  atomic = true

  wait = true

  timeout = var.cluster_autoscaler_timeout

  set {
    name = "autoDiscovery.clusterName"

    value = module.eks.cluster_name
  }

  set {
    name = "awsRegion"

    value = var.aws_region
  }

  set {
    name = "rbac.create"

    value = "true"
  }

  set {
    name = "cloudProvider"

    value = "aws"
  }

  set {
    name = "extraArgs.balance-similar-node-groups"

    value = "true"
  }

  set {
    name = "extraArgs.skip-nodes-with-system-pods"

    value = "false"
  }

  set {
    name = "extraArgs.skip-nodes-with-local-storage"

    value = "false"
  }

  set {
    name = "extraArgs.expander"

    value = "least-waste"
  }

  depends_on = [
    module.eks
  ]
}