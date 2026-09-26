# ActivityPub discovery hand-off (activitypub_host).
#
# A handle @user@<domain_name> only resolves if <domain_name>/.well-known/webfinger
# reaches the server that owns the account. These tests pin the three contracts:
# nothing renders by default, the query string survives the redirect (the
# Bridgy Fed rule removed in 0.7.0 dropped it and so could never name an
# account), and only the three discovery paths move.

mock_provider "aws" {
  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::111122223333:function/redirect-function"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:111122223333:certificate/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  domain_name     = "example.test"
  s3_bucket_name  = "example-bucket"
  route53_zone_id = "Z00000000000000000000"
}

run "off_by_default_leaves_the_function_unchanged" {
  command = plan

  assert {
    condition     = !strcontains(aws_cloudfront_function.redirect_function[0].code, "webfinger")
    error_message = "the ActivityPub block must not render unless activitypub_host is set"
  }
}

run "on_redirects_the_three_discovery_paths_with_the_query" {
  command = plan

  variables {
    activitypub_host = "gotosocial.example.test"
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.redirect_function[0].code, "[\"/.well-known/webfinger\",\"/.well-known/host-meta\",\"/.well-known/nodeinfo\"].indexOf(uri) !== -1")
    error_message = "expected an exact match on webfinger, host-meta and nodeinfo, and nothing else"
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.redirect_function[0].code, "\"https://gotosocial.example.test\" + uri + aqs")
    error_message = "the Location must be the ActivityPub host plus the original path and rebuilt query string"
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.redirect_function[0].code, "var aq = request.querystring;")
    error_message = "the query string must be rebuilt: a webfinger Location without ?resource= cannot name an account"
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.redirect_function[0].code, "max-age=3600")
    error_message = "the hand-off must cache for an hour, not the redirect table's year, so a moved server is not pinned"
  }
}

run "atproto_did_still_answers_alongside" {
  command = plan

  variables {
    activitypub_host = "gotosocial.example.test"
    atproto_did      = "did:plc:example"
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.redirect_function[0].code, "uri === \"/.well-known/atproto-did\"") && strcontains(aws_cloudfront_function.redirect_function[0].code, "webfinger")
    error_message = "the Bluesky and ActivityPub handles must coexist on one domain"
  }
}

run "rejects_a_url_instead_of_a_hostname" {
  command = plan

  variables {
    activitypub_host = "https://gotosocial.example.test/"
  }

  expect_failures = [var.activitypub_host]
}
