# The security_headers object grew optional fields (HSTS, nosniff, referrer
# policy, frame options). These tests pin two things: a consumer that passes
# only a CSP still gets exactly one header, and each new field emits its own
# header block when set.

variables {
  domain_name     = "example.test"
  s3_bucket_name  = "example-test-bucket"
  route53_zone_id = "Z00000000000000000000"
}

run "csp_only_consumer_is_unchanged" {
  command = plan

  variables {
    security_headers = {
      content_security_policy = "frame-src https://example.test"
    }
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 1
    error_message = "a security_headers consumer should get exactly one policy"
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].security_headers_config[0].content_security_policy) == 1
    error_message = "the CSP block should still be emitted"
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].security_headers_config[0].strict_transport_security) == 0
    error_message = "HSTS must not appear unless the caller asks for it"
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this[0].security_headers_config[0].content_type_options) == 0
    error_message = "nosniff must not appear unless the caller asks for it"
  }
}

run "every_header_is_emitted_when_set" {
  command = plan

  variables {
    security_headers = {
      content_security_policy = "frame-src https://example.test"
      strict_transport_security = {
        max_age_sec = 31536000
      }
      content_type_options_nosniff = true
      referrer_policy              = "strict-origin-when-cross-origin"
      frame_option                 = "SAMEORIGIN"
    }
  }

  assert {
    condition     = aws_cloudfront_response_headers_policy.this[0].security_headers_config[0].strict_transport_security[0].access_control_max_age_sec == 31536000
    error_message = "HSTS max-age should carry through"
  }

  assert {
    condition     = aws_cloudfront_response_headers_policy.this[0].security_headers_config[0].strict_transport_security[0].include_subdomains == false
    error_message = "include_subdomains should default to false: a subdomain without HTTPS would break"
  }

  assert {
    condition     = aws_cloudfront_response_headers_policy.this[0].security_headers_config[0].referrer_policy[0].referrer_policy == "strict-origin-when-cross-origin"
    error_message = "referrer policy should carry through"
  }

  assert {
    condition     = aws_cloudfront_response_headers_policy.this[0].security_headers_config[0].frame_options[0].frame_option == "SAMEORIGIN"
    error_message = "frame option should carry through"
  }
}

run "no_policy_without_security_headers" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 0
    error_message = "a consumer that sets no security_headers must get no policy"
  }
}
