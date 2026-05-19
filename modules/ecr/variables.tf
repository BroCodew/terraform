variable "repository_name" {
  description = "ECR repository name."
  type        = string
}

variable "image_tag_mutability" {
  description = "ECR image tag mutability setting."
  type        = string
}

variable "scan_on_push" {
  description = "Whether ECR scans images on push."
  type        = bool
}

variable "common_tags" {
  description = "Tags applied to ECR resources."
  type        = map(string)
  default     = {}
}
