resource "helm_release" "metrics_server" {
  name = var.metrics_server_release_name

  repository = var.metrics_server_repository

  chart = var.metrics_server_chart

  namespace = var.metrics_server_namespace

  create_namespace = var.metrics_server_create_namespace

  timeout = var.metrics_server_timeout

  wait = var.metrics_server_wait

  cleanup_on_fail = var.metrics_server_cleanup_on_fail

  atomic = var.metrics_server_atomic

  dependency_update = var.metrics_server_dependency_update

  depends_on = [
    module.eks
  ]
}