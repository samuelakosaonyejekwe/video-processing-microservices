variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "instance_profile_name" {
  type = string
}

variable "jenkins_instance_type" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "ubuntu_ami_owners" {
  type = list(string)
}

variable "ubuntu_ami_name_filter" {
  type = list(string)
}

variable "docker_gpg_url" {
  type = string
}

variable "docker_repo_url" {
  type = string
}

variable "jenkins_gpg_url" {
  type = string
}

variable "jenkins_repo_url" {
  type = string
}

variable "awscli_zip_url" {
  type = string
}

variable "kubectl_stable_url" {
  type = string
}

variable "kubectl_binary_base_url" {
  type = string
}

variable "helm_install_script_url" {
  type = string
}

variable "hashicorp_gpg_url" {
  type = string
}

variable "hashicorp_repo_url" {
  type = string
}

variable "eksctl_download_url" {
  type = string
}

variable "jenkins_container_image" {
  type = string
}

variable "jenkins_container_name" {
  type = string
}

variable "jenkins_volume_name" {
  type = string
}

variable "jenkins_host_port" {
  type = number
}

variable "jenkins_agent_port" {
  type = number
}

variable "jenkins_root_volume_size" {
  type = number
}