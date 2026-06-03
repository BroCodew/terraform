output "fqdn" {
  description = "The fully qualified domain name of the created record."
  value       = aws_route53_record.app.fqdn
}

output "name" {
  description = "The record name that was created."
  value       = aws_route53_record.app.name
}
