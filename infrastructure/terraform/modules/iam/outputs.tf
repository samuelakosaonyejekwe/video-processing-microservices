output "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role."
  value       = aws_iam_role.eks_cluster_role.arn
}

output "node_role_arn" {
  description = "ARN of the EKS node IAM role."
  value       = aws_iam_role.eks_node_role.arn
}

output "jenkins_instance_profile_name" {
  description = "Name of the Jenkins IAM instance profile."
  value       = aws_iam_instance_profile.jenkins_profile.name
}
