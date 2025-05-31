resource "aws_s3_bucket" "bucket" {
  bucket        = local.name
  bucket_prefix = local.bucket_prefix
  force_destroy = var.force_destroy
  tags          = local.merged_tags
}

resource "aws_s3_bucket_ownership_controls" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.bucket]
  bucket     = aws_s3_bucket.bucket.id
  acl        = var.acl
}

resource "aws_s3_bucket_policy" "bucket" {
  count  = var.policy != null ? 1 : 0
  bucket = aws_s3_bucket.bucket.id
  policy = var.policy
}

resource "aws_s3_bucket_website_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  index_document {
    suffix = lookup(var.website, "index_document", "index.html")
  }

  error_document {
    key = lookup(var.website, "error_document", "error.html")
  }

  dynamic "routing_rule" {
    for_each = try(var.website.routing_rules, [])
    content {
      condition {
        key_prefix_equals = routing_rule.value.condition.key_prefix_equals
      }
      redirect {
        host_name               = routing_rule.value.redirect.host_name
        http_redirect_code      = routing_rule.value.redirect.http_redirect_code
        protocol                = routing_rule.value.redirect.protocol
        replace_key_prefix_with = routing_rule.value.redirect.replace_key_prefix_with
      }
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "bucket" {
  count  = length(var.cors_rule) != 0 ? 1 : 0
  bucket = aws_s3_bucket.bucket.id

  dynamic "cors_rule" {
    for_each = [var.cors_rule]
    content {
      allowed_headers = lookup(cors_rule.value, "allowed_headers", null)
      allowed_methods = lookup(cors_rule.value, "allowed_methods", null)
      allowed_origins = lookup(cors_rule.value, "allowed_origins", null)
      expose_headers  = lookup(cors_rule.value, "expose_headers", null)
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", null)
    }
  }
}

resource "aws_s3_bucket_versioning" "bucket" {
  count  = length(var.versioning) != 0 ? 1 : 0
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status = lookup(var.versioning, "enabled", true) ? "Enabled" : "Disabled"
    mfa_delete = lookup(var.versioning, "mfa_delete", null)
  }
}

resource "aws_s3_bucket_logging" "bucket" {
  count  = length(var.logging) != 0 ? 1 : 0
  bucket = aws_s3_bucket.bucket.id

  target_bucket = lookup(var.logging, "target_bucket", null)
  target_prefix = lookup(var.logging, "target_prefix", null)
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  count  = length(var.lifecycle_rule) != 0 ? 1 : 0
  bucket = aws_s3_bucket.bucket.id

  dynamic "rule" {
    for_each = var.lifecycle_rule
    content {
      id     = lookup(rule.value, "id", null)
      status = lookup(rule.value, "enabled", false) ? "Enabled" : "Disabled"

      dynamic "filter" {
        for_each = lookup(rule.value, "prefix", null) != null ? [1] : []
        content {
          prefix = rule.value.prefix
        }
      }

      dynamic "expiration" {
        for_each = length(keys(lookup(rule.value, "expiration", {}))) == 0 ? [] : [lookup(rule.value, "expiration", {})]
        content {
          date                         = lookup(expiration.value, "date", null)
          days                         = lookup(expiration.value, "days", null)
          expired_object_delete_marker = lookup(expiration.value, "expired_object_delete_marker", null)
        }
      }

      dynamic "transition" {
        for_each = length(keys(lookup(rule.value, "transition", {}))) == 0 ? [] : [lookup(rule.value, "transition", {})]
        content {
          date          = lookup(transition.value, "date", null)
          days          = lookup(transition.value, "days", null)
          storage_class = lookup(transition.value, "storage_class", null)
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = length(keys(lookup(rule.value, "noncurrent_version_expiration", {}))) == 0 ? [] : [lookup(rule.value, "noncurrent_version_expiration", {})]
        content {
          noncurrent_days = lookup(noncurrent_version_expiration.value, "days", null)
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = length(keys(lookup(rule.value, "noncurrent_version_transition", {}))) == 0 ? [] : [lookup(rule.value, "noncurrent_version_transition", {})]
        content {
          noncurrent_days = lookup(noncurrent_version_transition.value, "days", null)
          storage_class   = lookup(noncurrent_version_transition.value, "storage_class", null)
        }
      }
    }
  }
}

resource "aws_s3_bucket_accelerate_configuration" "bucket" {
  count  = var.acceleration_status != null ? 1 : 0
  bucket = aws_s3_bucket.bucket.id
  status = var.acceleration_status
}

resource "aws_s3_bucket_request_payment_configuration" "bucket" {
  count  = var.request_payer != null ? 1 : 0
  bucket = aws_s3_bucket.bucket.id
  payer  = var.request_payer
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  count  = length(var.server_side_encryption_configuration) != 0 ? 1 : 0
  bucket = aws_s3_bucket.bucket.id

  dynamic "rule" {
    for_each = [var.server_side_encryption_configuration]
    content {
      apply_server_side_encryption_by_default {
        kms_master_key_id = lookup(rule.value, "kms_master_key_id", null)
        sse_algorithm     = lookup(rule.value, "sse_algorithm", null)
      }
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "bucket" {
  count  = length(var.object_lock_configuration) != 0 ? 1 : 0
  bucket = aws_s3_bucket.bucket.id

  dynamic "rule" {
    for_each = [var.object_lock_configuration]
    content {
      default_retention {
        mode  = lookup(rule.value.default_retention, "mode", null)
        days  = lookup(rule.value.default_retention, "days", null)
        years = lookup(rule.value.default_retention, "years", null)
      }
    }
  }
}

resource "aws_s3_bucket_object" "readme" {
  count   = var.create_readme ? 1 : 0
  bucket  = aws_s3_bucket.bucket.id
  key     = "README.md"
  content = templatefile("${path.module}/files/README.tpl.md", { ADDITIONAL_CONTENT = var.readme_additions })
}
