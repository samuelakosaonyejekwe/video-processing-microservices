data "aws_ami" "ubuntu" {

  most_recent = true

  owners = var.ubuntu_ami_owners

  filter {

    name = "name"

    values = var.ubuntu_ami_name_filter
  }

  filter {

    name = "virtualization-type"

    values = ["hvm"]
  }
}

resource "aws_instance" "jenkins" {

  ami = data.aws_ami.ubuntu.id

  instance_type = var.jenkins_instance_type

  subnet_id = var.subnet_id

  vpc_security_group_ids = var.security_group_ids

  iam_instance_profile = var.instance_profile_name

  associate_public_ip_address = true

  metadata_options {

    http_endpoint = "enabled"

    http_tokens = "required"
  }

  root_block_device {

    volume_size = var.jenkins_root_volume_size

    volume_type = "gp3"

    encrypted = true
  }

  user_data = base64encode(

    templatefile(

      "${path.module}/user-data.sh.tpl",

      {

        aws_region = var.aws_region

        eks_cluster = var.eks_cluster_name

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
      }
    )
  )

  tags = {

    Name = "${var.project_name}-${var.environment}-jenkins"
  }
}

resource "aws_eip" "jenkins" {

  domain = "vpc"

  instance = aws_instance.jenkins.id

  tags = {

    Name = "${var.project_name}-${var.environment}-jenkins-eip"
  }
}