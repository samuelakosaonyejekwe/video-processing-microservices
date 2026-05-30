resource "aws_ecr_repository" "repos" {
  for_each = toset(var.ecr_repositories)

  name = "${var.project_name}/${each.value}"

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.value}"
  }
}