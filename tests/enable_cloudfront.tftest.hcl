# enable_cloudfront = false is for a site whose domain is served somewhere else,
# so the distribution is maintained and paid for but never on the serving path.
#
# The gate must take down everything that only exists to serve the distribution
# (both edge functions, the response-headers policy, the alias records) and leave
# the things that outlive it (the S3 bucket, the certificate) alone. It must also
# stay invisible to the 12 consumers that never set it.

variables {
  domain_name     = "example.com"
  s3_bucket_name  = "example-bucket"
  route53_zone_id = "Z00000000000000000000"
}

run "enabled_by_default_so_existing_consumers_see_no_diff" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.this) == 1
    error_message = "A consumer that never sets enable_cloudfront must still get a distribution"
  }

  assert {
    condition     = length(aws_cloudfront_function.redirect_function) == 1
    error_message = "The redirect function must exist by default"
  }

  assert {
    condition     = length(aws_route53_record.this) == 1
    error_message = "The alias record must exist by default"
  }
}

run "disabled_creates_no_distribution" {
  command = plan

  variables {
    enable_cloudfront = false
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this) == 0
    error_message = "enable_cloudfront = false must create no distribution"
  }

  assert {
    condition     = length(aws_route53_record.this) == 0
    error_message = "The alias records point at the distribution, so they must go with it"
  }
}

run "disabled_takes_both_edge_functions_with_it" {
  command = plan

  variables {
    enable_cloudfront   = false
    bsky_oembed_enabled = true
    redirects           = [{ from = "/old/", to = "/new/" }]
  }

  assert {
    condition     = length(aws_cloudfront_function.redirect_function) == 0
    error_message = "A function with no distribution to run on is an orphan; it must not be created"
  }

  assert {
    condition     = length(aws_cloudfront_function.bsky_oembed_function) == 0
    error_message = "bsky_oembed_enabled must not resurrect a function when CloudFront is off"
  }
}

run "disabled_creates_no_response_headers_policy" {
  command = plan

  variables {
    enable_cloudfront = false
    security_headers = {
      content_security_policy = "frame-src https://example.test"
    }
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 0
    error_message = "The policy is only attachable to a distribution, so it must go with it"
  }
}

run "disabled_keeps_the_bucket_and_the_certificate" {
  command = plan

  variables {
    enable_cloudfront = false
  }

  # bucket_id and certificate_arn are computed, so they are null in any plan and
  # prove nothing here. Assert instead on things known at plan time. Both of
  # these references fail the test outright if the resource stops being planned,
  # which is the regression this run exists to catch.

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == false
    error_message = "The bucket holds the content and outlives any CDN in front of it; it must still be planned"
  }

  assert {
    condition     = output.certificate_domain_name == "example.com"
    error_message = "Re-issuing a certificate means waiting on DNS validation again; keep it so re-enabling is one apply"
  }
}

run "disabled_leaves_distribution_outputs_null_rather_than_erroring" {
  command = plan

  variables {
    enable_cloudfront = false
  }

  assert {
    condition     = output.distribution_id == null
    error_message = "Every distribution output must degrade to null, not blow up the plan of a consumer that reads it"
  }

  assert {
    condition     = output.distribution_domain_name == null
    error_message = "distribution_domain_name must be null when there is no distribution"
  }

  assert {
    condition     = length(output.route53_record_names) == 0
    error_message = "route53_record_names must be empty when no records are created"
  }
}
