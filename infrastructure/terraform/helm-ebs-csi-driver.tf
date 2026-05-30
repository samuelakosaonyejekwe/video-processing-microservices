resource "helm_release" "aws_ebs_csi_driver" {

  name = var.ebs_csi_driver_release_name

  repository = var.ebs_csi_driver_repository

  chart = var.ebs_csi_driver_chart

  namespace = var.ebs_csi_driver_namespace

  create_namespace = var.ebs_csi_driver_create_namespace

  timeout = var.ebs_csi_driver_timeout

  atomic = var.ebs_csi_driver_atomic

  cleanup_on_fail = var.ebs_csi_driver_cleanup_on_fail

  wait = var.ebs_csi_driver_wait

  dependency_update = var.ebs_csi_driver_dependency_update

  depends_on = [
    module.eks
  ]
}