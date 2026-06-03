output "certificate_arn" {
  description = "ARN of the validated ACM certificate. Use this when attaching the certificate to an ALB listener."
  value       = aws_acm_certificate.this.arn
}

output "certificate_status" {
  description = "Current status of the certificate (PENDING_VALIDATION, ISSUED, etc)."
  value       = aws_acm_certificate.this.status
}
