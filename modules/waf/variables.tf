variable "name" {
  description = "Name of the WAF Web ACL."
  type        = string
}

variable "alb_arn" {
  description = "ARN of the ALB to associate the WAF with."
  type        = string
}

variable "rate_limit" {
  description = "Rate limit (requests per 5 minutes per IP)."
  type        = number
  default     = 2000
}

variable "common_tags" {
  description = "Tags applied to WAF resources."
  type        = map(string)
  default     = {}
}
