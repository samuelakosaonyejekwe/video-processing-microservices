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