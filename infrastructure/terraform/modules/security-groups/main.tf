resource "aws_security_group" "eks" {

  name = "${var.project_name}-${var.environment}-eks-sg"

  description = "EKS security group"

  vpc_id = var.vpc_id

  ingress {

    from_port = 443

    to_port = 443

    protocol = "tcp"

    description = "kubectl / GitHub Actions API access"

    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {

    from_port = 6443

    to_port = 6443

    protocol = "tcp"

    description = "Kubernetes API (internal)"

    cidr_blocks = [var.vpc_cidr]
  }

  ingress {

    from_port = 5672

    to_port = 5672

    protocol = "tcp"

    description = "RabbitMQ AMQP (internal)"

    cidr_blocks = [var.vpc_cidr]
  }

  ingress {

    from_port = 15672

    to_port = 15672

    protocol = "tcp"

    description = "RabbitMQ management (internal)"

    cidr_blocks = [var.vpc_cidr]
  }

  ingress {

    from_port = 27017

    to_port = 27017

    protocol = "tcp"

    description = "MongoDB (internal)"

    cidr_blocks = [var.vpc_cidr]
  }

  ingress {

    from_port = 5432

    to_port = 5432

    protocol = "tcp"

    description = "PostgreSQL (internal)"

    cidr_blocks = [var.vpc_cidr]
  }

  # trivy:ignore:AVD-AWS-0104
  egress {

    from_port = 0

    to_port = 0

    protocol = "-1"

    description = "Allow all egress; EKS nodes route internet traffic through NAT gateway"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {

    Name = "${var.project_name}-${var.environment}-eks-sg"

    Environment = var.environment

    Terraform = "true"
  }
}

resource "aws_security_group" "jenkins" {

  name_prefix = "${var.project_name}-${var.environment}-jenkins-"

  description = "Jenkins security group"

  vpc_id = var.vpc_id

  ingress {

    from_port = 8080

    to_port = 8080

    protocol = "tcp"

    description = "Jenkins web UI"

    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {

    from_port = 22

    to_port = 22

    protocol = "tcp"

    description = "SSH restricted to VPC CIDR; use SSM Session Manager for external access"

    cidr_blocks = [var.vpc_cidr]
  }

  # trivy:ignore:AVD-AWS-0104
  egress {

    from_port = 0

    to_port = 0

    protocol = "-1"

    description = "Allow all egress for package downloads, ECR/DockerHub pushes, and GitHub API"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {

    Name = "${var.project_name}-${var.environment}-jenkins-sg"

    Environment = var.environment

    Terraform = "true"
  }
}
