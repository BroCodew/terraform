variable "domain_name" {
  description = "Primary domain name for the ACM certificate (e.g. app.terraformaws.online or terraformaws.online)."
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional domain names (SANs) to include in the certificate, e.g. [\"www.terraformaws.online\"]."
  type        = list(string)
  default     = []
}

variable "zone_id" {
  description = "The ID of the Route53 hosted zone where DNS validation records will be created."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to ACM resources."
  type        = map(string)
  default     = {}
}
