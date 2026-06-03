variable "zone_id" {
  description = "The Route53 hosted zone ID (e.g. Z02237983SGZXT8DWH3PD)."
  type        = string
}

variable "name" {
  description = "The name for the record. Use empty string \"\" for apex/root domain (terraformaws.online). Use \"app\" for app.terraformaws.online."
  type        = string
  default     = ""
}

variable "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer (from alb module output)."
  type        = string
}

variable "alb_zone_id" {
  description = "The canonical hosted zone ID of the ALB (from alb module output alb_zone_id). This is NOT the same as the Route53 zone ID."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to the Route53 record (optional)."
  type        = map(string)
  default     = {}
}
