resource "aws_ecr_repository" "app" {
  name                 = "my-ecr-repo-tr"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "my-ecr-repo-tr"
  }
}

