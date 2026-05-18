module "acm_certificate" {
  source = "./modules/terraform-aws-acm-certificate"
  //version = "1.2.1"

  domain_name            = var.domain_name
  alternate_domain_names = var.alternate_domain_names

  use_default_tags                    = true
  tags                                = var.acm_tags
  enable_certificate_transparency_log = var.acm_enable_certificate_transparency_log
  route53_zone_id                     = var.route53_zone_id
}

module "s3_bucket" {
  source = "./modules/terraform-aws-s3-bucket"
  //version = "1.2.1"

  name       = var.s3_bucket_name
  use_prefix = var.s3_use_prefix
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${module.s3_bucket.arn}/*"
      }
    ]
  })
  acl              = "private"
  use_default_tags = var.s3_use_default_tags
  tags             = local.s3_merged_tags
  force_destroy    = var.s3_force_destroy
  create_readme    = var.s3_create_readme
  website          = var.s3_website
}

# Add bucket public access block to ensure website access
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = module.s3_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_cloudfront_function" "redirect_function" {
  name    = "redirect-function"
  runtime = "cloudfront-js-1.0"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      if (uri.startsWith("/.well-known/host-meta")) {
        return {
          statusCode: 302,
          statusDescription: "Found",
          headers: {
            "location": { value: "https://fed.brid.gy" + uri }
          }
        };
      }

      if (uri.startsWith("/.well-known/webfinger")) {
        return {
          statusCode: 302,
          statusDescription: "Found",
          headers: {
            "location": { value: "https://fed.brid.gy" + uri }
          }
        };
      }
%{if var.atproto_did != null}
      if (uri === "/.well-known/atproto-did") {
        return {
          statusCode: 200,
          statusDescription: "OK",
          headers: {
            "content-type": { value: "text/plain" }
          },
          body: "${var.atproto_did}"
        };
      }
%{endif}
      return request;
    }
  EOT
}

resource "aws_cloudfront_function" "bsky_oembed_function" {
  count   = var.bsky_oembed_enabled ? 1 : 0
  name    = "bsky-oembed-function"
  runtime = "cloudfront-js-1.0"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      // Rewrite /api/bsky-oembed to /oembed for the Bluesky origin
      if (uri.startsWith("/api/bsky-oembed")) {
        request.uri = uri.replace("/api/bsky-oembed", "/oembed");
      }

      return request;
    }
  EOT
}



# -----------------------------------------------------------------------------
# Response-headers policy (ADR-MCEJU-003 / AC-3)
#
# Mutual-exclusion gate: setting BOTH var.security_headers and
# var.response_headers_policy_id is forbidden. The precondition fails the
# plan with both variable names in the error message so callers see the
# ambiguity at the earliest possible point. (variable-level cross-variable
# validation requires Terraform/OpenTofu 1.9+; terraform_data preconditions
# work since Terraform 1.4 / OpenTofu day-1.)
# -----------------------------------------------------------------------------

resource "terraform_data" "validate_security_headers_exclusive" {
  lifecycle {
    precondition {
      condition     = !(var.security_headers != null && var.response_headers_policy_id != null)
      error_message = "var.security_headers and var.response_headers_policy_id are mutually exclusive — pass either a structured security_headers object OR a pre-built response_headers_policy_id, not both."
    }
  }
}

# Module-owned response-headers policy, created only when the structured
# security_headers variable is set and the pass-through escape hatch is not.
# When response_headers_policy_id is non-null, the caller's pre-built policy
# takes precedence and this resource is skipped.

resource "aws_cloudfront_response_headers_policy" "this" {
  count = var.security_headers != null && var.response_headers_policy_id == null ? 1 : 0

  name    = "${var.s3_bucket_name}-response-headers"
  comment = "Module-managed response-headers policy for ${var.domain_name}. Generated from var.security_headers."

  security_headers_config {
    content_security_policy {
      content_security_policy = var.security_headers.content_security_policy
      override                = true
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  aliases = length(local.concatenated_records) > 0 ? local.concatenated_records : [var.domain_name]
  comment = var.cloudfront_comment

  # TODO: multiples allowed
  #  custom_error_response {
  #    error_code = 0
  #  }

  # TODO: turn into variable
  #  dynamic "default_cache_behavior" {
  #    for_each = var.default_cache_behavior
  #
  #    content {
  #      allowed_methods = lookup(default_cache_behavior.value, "allowed_methods", null)
  #      cached_methods = lookup(default_cache_behavior.value, "cached_methods", null)
  #      target_origin_id = lookup(default_cache_behavior.value, "target_origin_id", null)
  #      expose_headers  = lookup(default_cache_behavior.value, "expose_headers", null)
  #      max_age_seconds = lookup(default_cache_behavior.value, "max_age_seconds", null)
  #    }
  #  }

  default_cache_behavior {
    target_origin_id = local.s3_origin_id
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    compress         = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect_function.arn
    }

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300
    max_ttl                = 3600

    # Resolved policy id (ADR-MCEJU-003):
    #   - caller's pre-built policy (var.response_headers_policy_id) wins
    #   - else module-owned policy generated from var.security_headers
    #   - else null (existing distribution behavior, no policy attached)
    # The mutual-exclusion precondition on terraform_data.validate_security_
    # headers_exclusive guarantees the first two branches are not both active.
    response_headers_policy_id = (
      var.response_headers_policy_id != null
      ? var.response_headers_policy_id
      : (var.security_headers != null
        ? aws_cloudfront_response_headers_policy.this[0].id
        : null
      )
    )
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.bsky_oembed_enabled ? [1] : []

    content {
      path_pattern           = var.bsky_oembed_path_pattern
      target_origin_id       = local.bsky_oembed_origin_id
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      compress               = false
      min_ttl                = 0
      default_ttl            = 300
      max_ttl                = 3600

      forwarded_values {
        query_string = true

        cookies {
          forward = "none"
        }
      }

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.bsky_oembed_function[0].arn
      }
    }
  }



  default_root_object = var.cloudfront_default_root_object

  enabled         = var.cloudfront_enabled
  is_ipv6_enabled = var.cloudfront_is_ipv6_enabled
  http_version    = var.cloudfront_http_version

  #  logging_config {
  #    include_cookies = false
  #    bucket          = "mylogs.s3.amazonaws.com"
  #    prefix          = "myprefix"
  #  }

  origin {
    domain_name = module.s3_bucket.website_endpoint
    origin_id   = local.s3_origin_id
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols = [
        "TLSv1",
        "TLSv1.1",
        "TLSv1.2",
      ]
    }
  }

  dynamic "origin" {
    for_each = var.bsky_oembed_enabled ? [1] : []

    content {
      domain_name = var.bsky_oembed_origin_domain_name
      origin_id   = local.bsky_oembed_origin_id

      custom_origin_config {
        http_port                = 80
        https_port               = 443
        origin_keepalive_timeout = 5
        origin_protocol_policy   = "https-only"
        origin_read_timeout      = 30
        origin_ssl_protocols     = ["TLSv1.2"]
      }
    }
  }



  # TODO: multiples allowed
  #  origin_group {
  #    origin_id = ""
  #    failover_criteria {
  #      status_codes = []
  #    }
  #    member {
  #      origin_id = ""
  #    }
  #  }

  price_class = var.cloudfront_price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = local.cloudfront_merged_tags

  viewer_certificate {
    acm_certificate_arn      = module.acm_certificate.arn
    minimum_protocol_version = var.cloudfront_minimum_protocol_version
    ssl_support_method       = var.cloudfront_ssl_support_method
  }

  depends_on = [module.acm_certificate]
}

resource "aws_route53_record" "this" {
  count = length(local.concatenated_records)

  zone_id = var.route53_zone_id
  name    = local.concatenated_records[count.index]
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
