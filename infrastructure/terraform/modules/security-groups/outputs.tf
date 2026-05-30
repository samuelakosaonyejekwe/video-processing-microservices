output "eks_security_group_id" {
  value = aws_security_group.eks.id
}

output "jenkins_security_group_id" {
  value = aws_security_group.jenkins.id
}