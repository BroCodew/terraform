variable "log_group_name" {
  description = "CloudWatch log group name."
  type        = string
}

variable "log_group_tag_name" {
  description = "Name tag for the CloudWatch log group."
  type        = string
}

variable "retention_in_days" {
  description = "CloudWatch log retention in days."
  type        = number
}

variable "common_tags" {
  description = "Tags applied to log resources."
  type        = map(string)
  default     = {}
}
