variable "domain_name" {
  type        = string
  description = "Domain name of website"
}

variable "alternate_domain_names" {
  type        = list(string)
  description = "Alternate Domain Names of Website"
  default     = []
}

variable "s3_bucket_name" {
  type        = string
  description = "Name of S3 Bucket"
}

variable "s3_use_prefix" {
  type        = bool
  description = "Toggle to use randomly-generated Prefix for Bucket Name"
  default     = false
}

variable "s3_policy" {
  type        = string
  description = "Policy (JSON) Document of S3 Bucket"
  default     = null
}

variable "s3_use_default_tags" {
  type        = bool
  description = "Toggle to enable creation of default tags for S3 Bucket, containing Terraform Workspace identifier"
  default     = true
}

variable "s3_tags" {
  type        = map(string)
  description = "Mapping of Tags of S3 Bucket"
  default     = {}
}

variable "s3_force_destroy" {
  type        = bool
  description = "Toggle to enable force-destruction of S3 Bucket"
  default     = false
}

variable "s3_create_readme" {
  type        = bool
  description = "Toggle creation of `README.md` in root of S3 Bucket"
  default     = false
}

variable "s3_website" {
  type        = map(string)
  description = "Map of Website configuration of S3 Bucket"
  default     = {}
}

variable "acm_use_default_tags" {
  type        = bool
  description = "Toggle to enable creation of default tags for ACM Certificate, containing Terraform Workspace identifier"
  default     = true
}

variable "acm_tags" {
  type        = map(string)
  description = "Mapping of Tags of ACM Certificate"
  default     = {}
}

variable "acm_enable_certificate_transparency_log" {
  type        = bool
  description = "Toggle to enable a Certificate Transparency Log"
  default     = true
}

variable "route53_zone_id" {
  type        = string
  description = "ID of Route 53 Zone to use for Certificate Validation"
}

variable "cloudfront_origin_access_identity_comment" {
  type        = string
  description = "Comment for CloudFront Origin Access Identity"
  default     = ""
}

variable "cloudfront_enabled" {
  type        = bool
  description = "Toggle to enable CloudFront Distribution"
  default     = true
}

variable "cloudfront_is_ipv6_enabled" {
  type        = bool
  description = "Toggle to enable IPv6 support for CloudFront Distribution"
  default     = true
}

variable "cloudfront_comment" {
  type        = string
  description = "Comment for CloudFront Distribution"
  default     = "Terraform-managed resource"
}

# TODO: turn into variable
variable "cloudfront_default_cache_behavior" {
  type        = map(any)
  description = "Default cache behavior for CloudFront Distribution"
  default     = {}
}

variable "cloudfront_default_root_object" {
  type        = string
  description = "Default Object to return for CloudFront Distribution"
  default     = "index.html"
}

variable "cloudfront_http_version" {
  type        = string
  description = "HTTP version for CloudFront Distribution"
  default     = "http2"
}

variable "cloudfront_price_class" {
  type        = string
  description = "Price class for CloudFront Distribution"
  default     = "PriceClass_100"
}

variable "cloudfront_use_default_tags" {
  type        = bool
  description = "Toggle to enable creation of default tags for CloudFront Distribution, containing Terraform Workspace identifier"
  default     = true
}

variable "cloudfront_tags" {
  type        = map(string)
  description = "Mapping of Tags of CloudFront Distribution"
  default     = {}
}

variable "cloudfront_minimum_protocol_version" {
  type        = string
  description = "Minimum version of SSL protocol to support for this CloudFront Distribution"
  default     = "TLSv1.1_2016"
}

variable "cloudfront_ssl_support_method" {
  type        = string
  description = "HTTPs request serving method for CloudFront Distribution"
  default     = "sni-only"
}

variable "atproto_did" {
  type        = string
  description = "The DID value to return for /.well-known/atproto-did requests"
  default     = null
}

# -----------------------------------------------------------------------------
# Edge redirects (ADR-016, ADR-017, ADR-018, ADR-019, ADR-021)
#
# Both variables default to today's behavior, so a consumer that sets neither
# keeps the function name `redirect-function` and a render that is byte-identical
# to the pre-0.7.0 code minus the removed Bridgy Fed blocks (ADR-020).
# -----------------------------------------------------------------------------

variable "redirects" {
  type        = list(object({ from = string, to = string }))
  description = "Edge 301 redirects, rendered into the viewer-request function as an exact-match lookup table. `from` is the old site-relative path (any of its `/`, no-slash, or `/index.html` spellings), `to` is the site-relative target used verbatim in the Location. A list, not a map, so duplicates can be reported with both targets. Empty leaves the rendered code unchanged."
  default     = []
  nullable    = false
}

variable "redirect_function_name" {
  type        = string
  description = "Name of the viewer-request CloudFront Function. The default is the legacy name, so no consumer is renamed. CloudFront Function names are unique per AWS account: a second site in the same account must set a distinct name, for example `unintelligent-design-us-redirect`. A rename is a create-before-destroy replacement (ADR-021); never bundle it with a list change."
  default     = "redirect-function"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,64}$", var.redirect_function_name))
    error_message = "redirect_function_name must match ^[A-Za-z0-9_-]{1,64}$ — the CloudFront Functions name rule."
  }
}

variable "bsky_oembed_enabled" {
  type        = bool
  description = "Enable Bluesky oEmbed proxy behavior on CloudFront"
  default     = false
}

variable "bsky_oembed_origin_domain_name" {
  type        = string
  description = "Domain name of the Bluesky oEmbed origin"
  default     = "embed.bsky.app"
}

variable "bsky_oembed_path_pattern" {
  type        = string
  description = "Path pattern used for Bluesky oEmbed requests"
  default     = "/api/bsky-oembed*"
}

# -----------------------------------------------------------------------------
# Response-headers policy (ADR-MCEJU-003)
#
# Two opt-in variables. Both default to null so existing callers see no
# behavioral change. Set exactly one — they are mutually exclusive; setting
# both fails the plan via the validation block on `terraform_data.validate_
# security_headers_exclusive` in main.tf.
# -----------------------------------------------------------------------------

variable "security_headers" {
  type = object({
    content_security_policy = optional(string)

    # Each field below is optional and emits its header only when set, so a
    # consumer that passes only content_security_policy keeps its current
    # policy byte-for-byte.
    strict_transport_security = optional(object({
      max_age_sec        = number
      include_subdomains = optional(bool, false)
      preload            = optional(bool, false)
    }))
    content_type_options_nosniff = optional(bool, false)
    referrer_policy              = optional(string)
    frame_option                 = optional(string)
  })
  description = "Optional structured security headers. When set, the module creates an aws_cloudfront_response_headers_policy from these fields and attaches it to the distribution's default cache behavior. Each field is emitted only when set. frame_option takes DENY or SAMEORIGIN; referrer_policy takes a CloudFront-supported value such as strict-origin-when-cross-origin. Mutually exclusive with response_headers_policy_id. Default null preserves existing distribution behavior."
  default     = null
}

variable "response_headers_policy_id" {
  type        = string
  description = "Optional pre-built aws_cloudfront_response_headers_policy id. When set, the distribution attaches it directly without creating a module-owned policy. Escape hatch for callers maintaining their own policies (e.g., AWS managed policies, multi-distribution shared policies). Mutually exclusive with security_headers. Default null preserves existing distribution behavior."
  default     = null
}

locals {
  default_tags = {
    TerraformManaged   = true
    TerraformWorkspace = terraform.workspace
  }

  # if `use_default_tags` is set to `true`, merge `tags` with `default_tags`
  # otherwise, use user-supplied `tags` mapping
  s3_merged_tags         = var.s3_use_default_tags ? merge(var.s3_tags, local.default_tags) : var.s3_tags
  acm_merged_tags        = var.acm_use_default_tags ? merge(var.acm_tags, local.default_tags) : var.acm_tags
  cloudfront_merged_tags = var.cloudfront_use_default_tags ? merge(var.cloudfront_tags, local.default_tags) : var.cloudfront_tags

  concatenated_records = concat([var.domain_name], var.alternate_domain_names)

  # if `use_prefix` is set to `true`, set `bucket_name` to `null`
  # thereby allowing Terraform to set the `bucket_prefix`
  s3_bucket_name = var.s3_use_prefix ? null : var.s3_bucket_name

  # if `use_prefix` is set to `false`, set `bucket_prefix` to `null`
  # thereby allowing Terraform to set the `bucket_name`
  s3_bucket_prefix = var.s3_use_prefix ? var.s3_bucket_name : null

  s3_origin_id          = "S3-${var.s3_bucket_name}"
  bsky_oembed_origin_id = "bsky_oembed_origin"

  cloudfront_origin_access_identity_comment = var.cloudfront_origin_access_identity_comment != "" ? var.cloudfront_origin_access_identity_comment : "Terraform-managed Origin Access Identity for ${var.domain_name}"
}
