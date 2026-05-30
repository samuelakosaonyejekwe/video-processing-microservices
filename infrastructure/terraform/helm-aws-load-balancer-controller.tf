resource "helm_release" "aws_load_balancer_controller" {

  name = var.aws_load_balancer_controller_name

  repository = var.aws_load_balancer_controller_repository

  chart = var.aws_load_balancer_controller_chart

  namespace = var.aws_load_balancer_controller_namespace

  create_namespace = false

  set {
    name = "clusterName"

    value = var.cluster_name
  }

  depends_on = [
    module.eks
  ]
}