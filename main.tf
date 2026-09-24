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

# -----------------------------------------------------------------------------
# Edge redirects: renderer, validator, and the function resource
# (ADR-016 .. ADR-021; rule catalogue V-01..V-10 in the consumer docs and README)
#
# There is exactly ONE code string, `local.redirect_function_code`. The resource
# uploads it and the budget output measures it, so the two can never disagree.
# With `redirects = []` the render is byte-identical to the pre-0.7.0 code minus
# the two removed Bridgy Fed blocks (golden test P-4), which keeps the plan of a
# consumer that configures nothing to a single in-place update.
# -----------------------------------------------------------------------------

locals {
  # CloudFront Function names are unique per AWS account, so two sites sharing a
  # literal name share one function: whichever applies last overwrites the other
  # and silently takes over its behavior. Derive from domain_name, which is
  # already unique per site, and let a consumer pin a legacy name explicitly.
  function_name_stem = substr(replace(replace(lower(var.domain_name), ".", "-"), "/[^a-z0-9-]/", ""), 0, 48)

  redirect_function_name    = coalesce(var.redirect_function_name, "${local.function_name_stem}-redirect")
  bsky_oembed_function_name = coalesce(var.bsky_oembed_function_name, "${local.function_name_stem}-bsky-oembed")

  redirect_budget  = 10240 # CloudFront Functions maximum code size, in bytes
  redirect_warn_at = 8192  # 80% of the budget: warn, but do not fail

  # V-01 charset. ASCII only, so `length()` (characters) equals bytes.
  redirect_path_re = "^/[A-Za-z0-9._~%/-]*$"

  # Paths this module answers itself, and the prefixes a list entry may never
  # claim. `/.well-known/` is reserved for identity and discovery whether or not
  # the module answers a path under it today (ADR-020).
  redirect_reserved_prefixes = ["/.well-known/", trimsuffix(var.bsky_oembed_path_pattern, "*")]
  redirect_module_paths      = var.atproto_did == null ? [] : ["/.well-known/atproto-did"]

  # N(p): drop a trailing "/index.html", else one trailing "/". Applied to the
  # table keys here and to request.uri at the edge, so all three spellings of an
  # old path reach the target in one hop.
  redirect_entries = [
    for e in var.redirects : {
      from  = e.from
      to    = e.to
      nfrom = endswith(e.from, "/index.html") ? substr(e.from, 0, length(e.from) - 11) : (endswith(e.from, "/") ? substr(e.from, 0, length(e.from) - 1) : e.from)
      nto   = endswith(e.to, "/index.html") ? substr(e.to, 0, length(e.to) - 11) : (endswith(e.to, "/") ? substr(e.to, 0, length(e.to) - 1) : e.to)
    }
  ]

  # Grouping form (`=> ...`) instead of a plain map, so that a duplicate old path
  # is reported by V-05 rather than blowing up as a raw "duplicate object key".
  redirect_grouped = { for e in local.redirect_entries : e.nfrom => e.to... }
  redirect_table   = { for k, v in local.redirect_grouped : k => v[0] }
  redirect_keys    = keys(local.redirect_table)
  redirect_hop     = { for k, v in { for e in local.redirect_entries : e.nfrom => e.nto... } : k => v[0] }

  # -- V-01 .. V-07 offenders ------------------------------------------------
  redirect_malformed = distinct(flatten([
    for e in var.redirects : [
      for p in [e.from, e.to] : p
      if !can(regex(local.redirect_path_re, p)) || length(regexall("//", p)) > 0
    ]
  ]))

  redirect_not_a_page = [
    for e in var.redirects : e.to
    if !endswith(e.to, "/") && !can(regex("^[^/]*[.][^/.]+$", element(split("/", e.to), length(split("/", e.to)) - 1)))
  ]

  redirect_root_old_path = [for e in var.redirects : e.from if e.from == "/"]

  redirect_reserved = [
    for e in var.redirects : e.from
    if anytrue([for p in local.redirect_reserved_prefixes : startswith(e.from, p)]) || e.from == "/.well-known"
  ]

  redirect_duplicates = [
    for k, v in local.redirect_grouped : format("%q sends to %s", k, join(" and ", formatlist("%q", v)))
    if length(v) > 1
  ]

  redirect_self = [for e in local.redirect_entries : e.from if e.nfrom == e.nto]

  # Chain and loop. HCL has no recursion, so the diagnostics unroll a bounded
  # number of hops: the detection (any target that is itself an old path) is
  # exact, the "loop" label and the suggested final target are best-effort.
  redirect_chains = [
    for e in local.redirect_entries : {
      from  = e.from
      to    = e.to
      nfrom = e.nfrom
      h1    = e.nto
      h2    = lookup(local.redirect_hop, e.nto, null)
    }
    if contains(local.redirect_keys, e.nto) && e.nfrom != e.nto
  ]

  redirect_chain_reports = [
    for c in local.redirect_chains :
    (c.h2 == c.nfrom || (c.h2 != null && lookup(local.redirect_hop, coalesce(c.h2, "\u0000"), null) == c.nfrom))
    ? format("loop: %q sends to %q, which comes back to it", c.from, c.to)
    : format("chain: %q sends to %q, which is itself an old path on this list; point it straight at %q", c.from, c.to,
    lookup(local.redirect_table, c.h2 == null ? c.h1 : (contains(local.redirect_keys, c.h2) ? c.h2 : c.h1), c.to))
  ]

  # -- render ----------------------------------------------------------------
  # The lookup block is emitted only for a non-empty list, and it carries its own
  # trailing blank line, so an empty list adds exactly zero bytes.
  redirect_block = length(var.redirects) == 0 ? "" : <<EOT
      var t = ${jsonencode(local.redirect_table)};
      var k = uri;
      if (k.slice(-11) === "/index.html") {
        k = k.slice(0, -11);
      } else if (k.slice(-1) === "/") {
        k = k.slice(0, -1);
      }
      var d = t[k];
      if (d) {
        var q = request.querystring;
        var s = "";
        var n, i, m;
        for (n in q) {
          m = q[n].multiValue;
          if (m) {
            for (i = 0; i < m.length; i++) {
              s += (s ? "&" : "?") + n + (m[i].value ? "=" + m[i].value : "");
            }
          } else {
            s += (s ? "&" : "?") + n + (q[n].value ? "=" + q[n].value : "");
          }
        }
        return {
          statusCode: 301,
          statusDescription: "Moved Permanently",
          headers: {
            "location": { value: "https://${var.domain_name}" + d + s },
            "cache-control": { value: "max-age=31536000" }
          }
        };
      }

EOT

  # A directory URL without a trailing slash is answered by the S3 website
  # origin with a 302. That is a temporary redirect for a permanent fact, and it
  # costs a trip to the origin. Answered at the edge with a 301 instead, when the
  # consumer asks for it. Runs after the redirect table, so an explicit entry
  # always wins. Files (a dot after the last slash) and /.well-known/ are skipped:
  # those are not directories, and one of them is this module's atproto-did.
  trailing_slash_code = <<EOT
      if (uri !== "/" && uri.slice(-1) !== "/" && uri.lastIndexOf(".") <= uri.lastIndexOf("/") && uri.indexOf("/.well-known/") !== 0) {
        var tq = request.querystring;
        var ts = "";
        var tn, ti, tm;
        for (tn in tq) {
          tm = tq[tn].multiValue;
          if (tm) {
            for (ti = 0; ti < tm.length; ti++) {
              ts += (ts ? "&" : "?") + tn + (tm[ti].value ? "=" + tm[ti].value : "");
            }
          } else {
            ts += (ts ? "&" : "?") + tn + (tq[tn].value ? "=" + tq[tn].value : "");
          }
        }
        return {
          statusCode: 301,
          statusDescription: "Moved Permanently",
          headers: {
            "location": { value: "https://${var.domain_name}" + uri + "/" + ts },
            "cache-control": { value: "max-age=86400" }
          }
        };
      }
EOT

  trailing_slash_block = var.canonical_trailing_slash ? local.trailing_slash_code : ""

  redirect_function_code = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;
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
${local.redirect_block}${local.trailing_slash_block}      return request;
    }
  EOT

  redirect_code_bytes   = length(local.redirect_function_code)
  redirect_code_percent = floor(local.redirect_code_bytes * 100 / local.redirect_budget)
}

resource "aws_cloudfront_function" "redirect_function" {
  count   = var.enable_cloudfront ? 1 : 0
  name    = local.redirect_function_name
  runtime = "cloudfront-js-1.0"
  publish = true
  code    = local.redirect_function_code

  lifecycle {
    # A rename creates and associates the new function before the old one is
    # deleted, so the distribution never points at a deleted function (ADR-021).
    # This adds no plan diff for a consumer that keeps the default name.
    create_before_destroy = true

    precondition {
      condition     = length(local.redirect_malformed) == 0
      error_message = "Redirect list rejected: V-01 (malformed path): ${join(", ", formatlist("%q", local.redirect_malformed))}. Every path must start with \"/\", use only A-Z a-z 0-9 . _ ~ % / -, and contain no \"//\", \"?\", \"#\", or whitespace. A target on another host is never allowed. Nothing was changed."
    }

    precondition {
      condition     = length(local.redirect_not_a_page) == 0
      error_message = "Redirect list rejected: V-02 (target is not a page): ${join(", ", formatlist("%q", local.redirect_not_a_page))}. A target must end in \"/\" or name a file, or the origin bounces the reader a second time. Nothing was changed."
    }

    precondition {
      condition     = length(local.redirect_root_old_path) == 0
      error_message = "Redirect list rejected: V-03 (site root as an old path): \"/\" cannot be redirected. Nothing was changed."
    }

    precondition {
      condition     = length(local.redirect_reserved) == 0
      error_message = "Redirect list rejected: V-04 (reserved path): ${join(", ", formatlist("%q", local.redirect_reserved))}. ${join(" and ", formatlist("%q", local.redirect_reserved_prefixes))} are reserved for identity and discovery and are never redirected by a content list. Nothing was changed."
    }

    precondition {
      condition     = length(local.redirect_duplicates) == 0
      error_message = "Redirect list rejected: V-05 (duplicate old path): ${join("; ", local.redirect_duplicates)}. Every spelling of one old path is the same entry: keep one. Nothing was changed."
    }

    precondition {
      condition     = length(local.redirect_self) == 0
      error_message = "Redirect list rejected: V-06 (self-redirect): ${join(", ", formatlist("%q", local.redirect_self))} sends to itself. Remove the entry. Nothing was changed."
    }

    precondition {
      condition     = length(local.redirect_chain_reports) == 0
      error_message = "Redirect list rejected: V-07 (${join("; ", local.redirect_chain_reports)}). Every old path must reach a surviving page in one hop. Nothing was changed."
    }

    precondition {
      condition     = local.redirect_code_bytes <= local.redirect_budget
      error_message = "Redirect list rejected: V-08 (over the edge code budget): the rendered function is ${local.redirect_code_bytes} bytes, and the CloudFront Functions limit is ${local.redirect_budget} bytes. Prune old redirects, or move the list to a larger store (a CloudFront KeyValueStore, which needs a newer provider). Nothing was changed."
    }

    precondition {
      condition     = alltrue([for p in local.redirect_module_paths : anytrue([for r in local.redirect_reserved_prefixes : startswith(p, r)])])
      error_message = "Redirect list rejected: V-10 (module self-check): this module answers ${join(", ", formatlist("%q", local.redirect_module_paths))}, and at least one of those paths is not covered by a reserved prefix, so a list entry could shadow it. Add the prefix to local.redirect_reserved_prefixes. Nothing was changed."
    }
  }
}

resource "aws_cloudfront_function" "bsky_oembed_function" {
  count   = var.enable_cloudfront && var.bsky_oembed_enabled ? 1 : 0
  name    = local.bsky_oembed_function_name
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

  lifecycle {
    # Same reason as redirect_function above (ADR-021): a rename is a
    # replacement, and CloudFront refuses to delete a function while a
    # distribution still associates it. Without this, a rename destroys this
    # function first and the apply fails against the live association.
    create_before_destroy = true
  }
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
  count = var.enable_cloudfront && var.security_headers != null && var.response_headers_policy_id == null ? 1 : 0

  name    = "${var.s3_bucket_name}-response-headers"
  comment = "Module-managed response-headers policy for ${var.domain_name}. Generated from var.security_headers."

  security_headers_config {
    dynamic "content_security_policy" {
      for_each = var.security_headers.content_security_policy != null ? [var.security_headers.content_security_policy] : []
      content {
        content_security_policy = content_security_policy.value
        override                = true
      }
    }

    dynamic "strict_transport_security" {
      for_each = var.security_headers.strict_transport_security != null ? [var.security_headers.strict_transport_security] : []
      content {
        access_control_max_age_sec = strict_transport_security.value.max_age_sec
        include_subdomains         = strict_transport_security.value.include_subdomains
        preload                    = strict_transport_security.value.preload
        override                   = true
      }
    }

    dynamic "content_type_options" {
      for_each = var.security_headers.content_type_options_nosniff ? [true] : []
      content {
        override = true
      }
    }

    dynamic "referrer_policy" {
      for_each = var.security_headers.referrer_policy != null ? [var.security_headers.referrer_policy] : []
      content {
        referrer_policy = referrer_policy.value
        override        = true
      }
    }

    dynamic "frame_options" {
      for_each = var.security_headers.frame_option != null ? [var.security_headers.frame_option] : []
      content {
        frame_option = frame_options.value
        override     = true
      }
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  count = var.enable_cloudfront ? 1 : 0

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
      function_arn = aws_cloudfront_function.redirect_function[0].arn
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
  count = var.enable_cloudfront ? length(local.concatenated_records) : 0

  zone_id = var.route53_zone_id
  name    = local.concatenated_records[count.index]
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this[0].domain_name
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}
