output "bucket_arn" {
  value       = module.s3_bucket.arn
  description = "ARN of the S3 Bucket"
}

output "bucket_id" {
  value       = module.s3_bucket.id
  description = "Identifier of the S3 Bucket"
}

output "bucket_hosted_zone_id" {
  value       = module.s3_bucket.hosted_zone_id
  description = "Route 53 Hosted Zone ID of the S3 Bucket"
}

output "certificate_arn" {
  value       = module.acm_certificate.arn
  description = "ARN of the ACM Certificate"
}

output "certificate_id" {
  value       = module.acm_certificate.id
  description = "Identifier of the ACM Certificate"
}

output "certificate_domain_name" {
  value       = module.acm_certificate.domain_name
  description = "Domain name(s) of the ACM Certificate"
}

# TODO: cloudfront outputs
output "distribution_id" {
  value       = one(aws_cloudfront_distribution.this[*].id)
  description = "Identifier for the CloudFront Distribution"
}

output "distribution_arn" {
  value       = one(aws_cloudfront_distribution.this[*].arn)
  description = "ARN of the CloudFront Distribution"
}

output "distribution_status" {
  value       = one(aws_cloudfront_distribution.this[*].status)
  description = "Status of the CloudFront Distribution"
}

output "distribution_active_trusted_signers" {
  value       = one(aws_cloudfront_distribution.this[*].trusted_signers)
  description = "Key Pair IDs that are able to sign private URLs for the CloudFront Distribution"
}

output "distribution_domain_name" {
  value       = one(aws_cloudfront_distribution.this[*].domain_name)
  description = "Domain Name of the CloudFront Distribution"
}

output "distribution_last_modified_time" {
  value       = one(aws_cloudfront_distribution.this[*].last_modified_time)
  description = "Date and time of last modification for the CloudFront Distribution"
}

output "distribution_in_progress_validation_batches" {
  value       = one(aws_cloudfront_distribution.this[*].in_progress_validation_batches)
  description = "Number of invalidation batches currently in progress for the CloudFront Distribution"
}

output "distribution_etag" {
  value       = one(aws_cloudfront_distribution.this[*].etag)
  description = "Identifier of Current Version of the CloudFront Distribution"
}

output "distribution_hosted_zone_id" {
  value       = one(aws_cloudfront_distribution.this[*].hosted_zone_id)
  description = "Route 53 Zone ID for the CloudFront Distribution"
}

#output "policy_document_json" {
#  value       = aws_iam_policy_document.this.json
#  description = "IAM Policy Document for S3 Bucket Policy (in JSON Format)"
#}

# V-09: the edge code budget, reported as a string rather than a `check` block,
# so `required_version` stays at >= 1.4.0 (ADR-019). Only V-08 (over the limit)
# fails the plan; this warns at 80% and is otherwise informational. Re-export it
# from the root to see it in the plan's "Changes to Outputs".
output "redirects_summary" {
  value = format(
    "%d redirects, %d of %d bytes (%d%%)%s",
    length(var.redirects),
    local.redirect_code_bytes,
    local.redirect_budget,
    local.redirect_code_percent,
    local.redirect_code_bytes < local.redirect_warn_at ? "" : format(
      "; WARNING: %d%% of the edge code budget used, %d bytes remain",
      local.redirect_code_percent,
      local.redirect_budget - local.redirect_code_bytes,
    ),
  )
  description = "Number of edge redirects published, and the rendered CloudFront Function size against the 10,240-byte limit. Carries a WARNING at 80% of the budget."
}

output "route53_record_names" {
  value       = aws_route53_record.this[*].name
  description = "Name of the Route 53 Record Name(s)"
}

output "route53_record_fqdn" {
  value       = aws_route53_record.this[*].fqdn
  description = "Name of the Route 53 Record FQDN"
}

output "redirect_function_name" {
  description = "Resolved name of the viewer-request CloudFront Function. Derived from domain_name unless redirect_function_name pins a legacy name. Names are unique per AWS account, so two sites reporting the same value share one function."
  value       = local.redirect_function_name
}

output "bsky_oembed_function_name" {
  description = "Resolved name of the Bluesky oEmbed CloudFront Function, or null when the behavior is disabled."
  value       = var.bsky_oembed_enabled ? local.bsky_oembed_function_name : null
}
