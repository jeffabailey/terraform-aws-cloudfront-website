# Function names are unique per AWS account. A shared literal makes two sites
# manage one function, and the second apply overwrites the first. These tests
# pin the derivation so that can't come back.

variables {
  domain_name     = "example.com"
  s3_bucket_name  = "example-bucket"
  route53_zone_id = "Z00000000000000000000"
}

run "derives_a_per_site_name_from_the_domain" {
  command = plan

  assert {
    condition     = output.redirect_function_name == "example-com-redirect"
    error_message = "Expected a name derived from domain_name, got ${output.redirect_function_name}"
  }
}

run "two_domains_never_collide" {
  command = plan

  variables {
    domain_name = "unintelligent-design.us"
  }

  assert {
    condition     = output.redirect_function_name == "unintelligent-design-us-redirect"
    error_message = "Expected unintelligent-design-us-redirect, got ${output.redirect_function_name}"
  }

  assert {
    condition     = output.redirect_function_name != "example-com-redirect"
    error_message = "Two different domains produced the same function name, which is the collision this module must prevent"
  }
}

run "legacy_name_can_be_pinned" {
  command = plan

  variables {
    domain_name            = "jeffbailey.us"
    redirect_function_name = "redirect-function"
  }

  assert {
    condition     = output.redirect_function_name == "redirect-function"
    error_message = "An explicit name must win, so a live distribution is never renamed out from under itself"
  }
}

run "bsky_name_is_also_per_site" {
  command = plan

  variables {
    domain_name         = "jeffbailey.us"
    bsky_oembed_enabled = true
  }

  assert {
    condition     = output.bsky_oembed_function_name == "jeffbailey-us-bsky-oembed"
    error_message = "Expected a derived bsky name, got ${output.bsky_oembed_function_name}"
  }
}

run "bsky_name_is_null_when_disabled" {
  command = plan

  assert {
    condition     = output.bsky_oembed_function_name == null
    error_message = "Disabled bsky behavior should report no function name"
  }
}
