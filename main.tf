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

  name             = var.s3_bucket_name
  use_prefix       = var.s3_use_prefix
  policy           = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "s3:GetObject"
        Resource = "${module.s3_bucket.arn}/*"
      }
    ]
  })
  acl              = "private"
  use_default_tags = var.s3_use_default_tags
  tags             = local.s3_merged_tags
  force_destroy    = var.s3_force_destroy
  create_readme    = var.s3_create_readme

  website = {
    index_document = "index.html"
    error_document = "error.html"
  }
}

# Add explicit website configuration
resource "aws_s3_bucket_website_configuration" "this" {
  bucket = module.s3_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
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

      return request;
    }
  EOT
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
