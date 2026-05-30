resource "helm_release" "keda" {

  name = var.keda_release_name

  repository = var.keda_helm_repository

  chart = var.keda_chart_name

  namespace = var.keda_namespace

  create_namespace = true

  cleanup_on_fail = true

  dependency_update = true

  timeout = 600

  atomic = true

  wait = true
}