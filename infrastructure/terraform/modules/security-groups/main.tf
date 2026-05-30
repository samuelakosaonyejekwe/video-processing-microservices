resource "aws_security_group" "eks" {

  name = "${var.project_name}-${var.environment}-eks-sg"

  description = "EKS security group"

  vpc_id = var.vpc_id

  ingress {

    from_port = 443

    to_port = 443

    protocol = "tcp"

    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {

    from_port = 6443

    to_port = 6443

    protocol = "tcp"

    cidr_blocks = [var.vpc_cidr]
  }

  ingress {

    from_port = 5672

    to_port = 5672

    protocol = "tcp"

    cidr_blocks = [var.vpc_cidr]
  }

  ingress {

    from_port = 15672

    to_port = 15672

    protocol = "tcp"

    cidr_blocks = [var.vpc_cidr]
  }

  ingress {

    from_port = 27017

    to_port = 27017

    protocol = "tcp"

    cidr_blocks = [var.vpc_cidr]
  }

  ingress {

    from_port = 5432

    to_port = 5432

    protocol = "tcp"

    cidr_blocks = [var.vpc_cidr]
  }

  egress {

    from_port = 0

    to_port = 0

    protocol = "-1"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
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

    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {

    from_port = 22

    to_port = 22

    protocol = "tcp"

    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {

    from_port = 0

    to_port = 0

    protocol = "-1"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {

    Name = "${var.project_name}-${var.environment}-jenkins-sg"

    Environment = var.environment

    Terraform = "true"
  }
}