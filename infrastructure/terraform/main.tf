module "vpc" {

  source = "./modules/vpc"

  project_name = var.project_name

  environment = var.environment

  vpc_cidr = var.vpc_cidr

  allowed_cidr_blocks = var.allowed_cidr_blocks

  availability_zones = var.availability_zones

  public_subnet_cidrs = var.public_subnet_cidrs

  private_subnet_cidrs = var.private_subnet_cidrs

  enable_nat_gateway = var.enable_nat_gateway

  single_nat_gateway = var.single_nat_gateway
}

module "security_groups" {

  source = "./modules/security-groups"

  project_name = var.project_name

  environment = var.environment

  vpc_id = module.vpc.vpc_id

  vpc_cidr = var.vpc_cidr

  allowed_cidr_blocks = var.allowed_cidr_blocks
}

module "iam" {

  source = "./modules/iam"

  project_name = var.project_name

  environment = var.environment
}

module "eks" {

  source = "./modules/eks"

  project_name = var.project_name

  environment = var.environment

  eks_cluster_name = var.eks_cluster_name

  vpc_id = module.vpc.vpc_id

  subnet_ids = module.vpc.private_subnet_ids

  cluster_role_arn = module.iam.cluster_role_arn

  node_role_arn = module.iam.node_role_arn

  security_group_ids = [
    module.security_groups.eks_security_group_id
  ]

  eks_node_instance_type = var.eks_node_instance_type

  eks_desired_size = var.eks_desired_size

  eks_min_size = var.eks_min_size

  eks_max_size = var.eks_max_size

  kubernetes_version = var.kubernetes_version

  enable_cluster_log_types = var.enable_cluster_log_types

  endpoint_private_access = var.endpoint_private_access

  endpoint_public_access = var.endpoint_public_access

  public_access_cidrs = var.public_access_cidrs

  node_disk_size = var.node_disk_size

  capacity_type = var.capacity_type

  ami_type = var.ami_type

  max_unavailable = var.max_unavailable

  tags = var.tags
}

module "ecr" {

  source = "./modules/ecr"

  project_name = var.project_name

  environment = var.environment

  ecr_repositories = var.ecr_repositories
}

module "jenkins" {

  source = "./modules/jenkins"

  project_name = var.project_name

  environment = var.environment

  subnet_id = element(
    module.vpc.public_subnet_ids,
    0
  )

  security_group_ids = [
    module.security_groups.jenkins_security_group_id
  ]

  instance_profile_name = module.iam.jenkins_instance_profile_name

  jenkins_instance_type = var.jenkins_instance_type

  aws_region = var.aws_region

  eks_cluster_name = var.eks_cluster_name

  ubuntu_ami_owners = var.ubuntu_ami_owners

  ubuntu_ami_name_filter = var.ubuntu_ami_name_filter

  docker_gpg_url = var.docker_gpg_url

  docker_repo_url = var.docker_repo_url

  jenkins_gpg_url = var.jenkins_gpg_url

  jenkins_repo_url = var.jenkins_repo_url

  awscli_zip_url = var.awscli_zip_url

  kubectl_stable_url = var.kubectl_stable_url

  kubectl_binary_base_url = var.kubectl_binary_base_url

  helm_install_script_url = var.helm_install_script_url

  hashicorp_gpg_url = var.hashicorp_gpg_url

  hashicorp_repo_url = var.hashicorp_repo_url

  eksctl_download_url = var.eksctl_download_url

  jenkins_container_image = var.jenkins_container_image

  jenkins_container_name = var.jenkins_container_name

  jenkins_volume_name = var.jenkins_volume_name

  jenkins_host_port = var.jenkins_host_port

  jenkins_agent_port = var.jenkins_agent_port

  jenkins_root_volume_size = var.jenkins_root_volume_size
}

module "keda" {

  source = "./modules/keda"

  keda_release_name = var.keda_release_name

  keda_helm_repository = var.keda_helm_repository

  keda_chart_name = var.keda_chart_name

  keda_namespace = var.keda_namespace

  depends_on = [
    module.eks
  ]
}
