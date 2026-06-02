resource "aws_ecr_repository" "repos" {
  for_each = toset(var.ecr_repositories)

  name = "${var.project_name}/${each.value}"

  # Immutable tags prevent a pushed image tag from being overwritten, ensuring
  # deployed digests are reproducible and tamper-evident. CI must publish unique
  # tags per build (e.g. the git SHA) rather than re-pushing a shared tag.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.value}"
  }
}

resource "aws_ecr_lifecycle_policy" "repos" {
  for_each = aws_ecr_repository.repos

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 10 images (any tag status)"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}