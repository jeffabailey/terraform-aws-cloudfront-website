# Render and budget contract for the edge redirect list (ADR-016 .. ADR-019).
#
# These are the enforcement tests named in the feature's architecture design:
#   P-4  an empty list is inert: the render equals the committed baseline
#   rule 2  there is one code string: the summary's bytes are the code's bytes
#   P-3  length() counts characters, so only ASCII paths are allowed
#
# Run with `tofu test` from the module root. The AWS provider is mocked: nothing
# here talks to AWS.

mock_provider "aws" {
  # The provider validates ARN-shaped arguments even against mocks, so the two
  # ARNs the distribution consumes have to look real.
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
  domain_name     = "jeffbailey.us"
  s3_bucket_name  = "jeffbaileyblog"
  route53_zone_id = "Z00000000000000000000"
  atproto_did     = "did:plc:iavkd7iqcdeawn2u7uj3rekb"
}

run "empty_list_renders_the_committed_baseline" {
  command = plan

  variables {
    redirects = []
  }

  assert {
    condition     = aws_cloudfront_function.redirect_function.code == file("${path.module}/tests/golden/redirect_function_empty.js")
    error_message = "With no redirects the rendered function must be byte-identical to tests/golden/redirect_function_empty.js, which is the pre-0.7.0 code minus the two Bridgy Fed blocks. A consumer that configures nothing must see one in-place update and nothing else (P-4, ADR-020)."
  }

  assert {
    condition     = output.redirects_summary == "0 redirects, 407 of 10240 bytes (3%)"
    error_message = "The budget line for an empty list changed: ${output.redirects_summary}."
  }
}

run "the_summary_measures_the_code_that_is_uploaded" {
  command = plan

  variables {
    redirects = [
      { from = "/blog/2019/11/23/gitgithub-com-permission-denied-publickey/", to = "/blog/2019/11/10/setting-ssh-key-permissions/" },
    ]
  }

  # Architecture rule 2: one code string. The summary must report the length of
  # the very string the resource uploads, not a re-derived estimate.
  assert {
    condition     = can(regex("^1 redirects, ${length(aws_cloudfront_function.redirect_function.code)} of 10240 bytes ", output.redirects_summary))
    error_message = "The budget line must report length() of the uploaded code. Code is ${length(aws_cloudfront_function.redirect_function.code)} bytes, summary says: ${output.redirects_summary}."
  }

  # The Location host comes from var.domain_name, never from the request, and
  # the generated 301 carries the one-year cache (ADR-018, NFR-6).
  assert {
    condition     = can(regex("\"https://jeffbailey\\.us\" \\+ d \\+ s", aws_cloudfront_function.redirect_function.code))
    error_message = "The rendered Location must be built from var.domain_name."
  }

  assert {
    condition     = can(regex("max-age=31536000", aws_cloudfront_function.redirect_function.code))
    error_message = "Generated 301s must carry cache-control: max-age=31536000 (ADR-018, maintainer decision)."
  }

  # N(from) keys the table, so the trailing-slash, slash-less and /index.html
  # spellings all reach the target in one hop (US-02).
  assert {
    condition     = can(regex("\\{\"/blog/2019/11/23/gitgithub-com-permission-denied-publickey\":\"/blog/2019/11/10/setting-ssh-key-permissions/\"\\}", aws_cloudfront_function.redirect_function.code))
    error_message = "The lookup table must be keyed by N(from) with the target verbatim."
  }
}

run "the_name_is_the_legacy_one_unless_a_consumer_asks" {
  command = plan

  variables {
    redirects = []
  }

  assert {
    condition     = aws_cloudfront_function.redirect_function.name == "redirect-function"
    error_message = "The default function name must stay the legacy one, or every consumer gets a replacement (ADR-021)."
  }
}

run "an_eighty_percent_list_warns_without_failing_the_plan" {
  command = plan

  variables {
    redirects = [
      for i in range(75) : {
        from = format("/blog/2019/01/%02d/merged-away-post-number-%03d/", i % 28 + 1, i)
        to   = format("/blog/2026/01/%02d/surviving-guide-number-%03d/", i % 28 + 1, i)
      }
    ]
  }

  assert {
    condition     = can(regex("^75 redirects, [0-9]+ of 10240 bytes \\([0-9]+%\\); WARNING: [0-9]+% of the edge code budget used, [0-9]+ bytes remain$", output.redirects_summary))
    error_message = "At or over 8192 bytes the summary must carry a WARNING naming the headroom left (V-09, AC-04.2). Got: ${output.redirects_summary}."
  }
}

run "a_fifty_entry_list_stays_under_the_warning_threshold" {
  command = plan

  # NFR-3: at least 50 entries fit in 80% of the budget.
  variables {
    redirects = [
      for i in range(50) : {
        from = format("/blog/2019/01/%02d/merged-away-post-number-%03d/", i % 28 + 1, i)
        to   = format("/blog/2026/01/%02d/surviving-guide-number-%03d/", i % 28 + 1, i)
      }
    ]
  }

  assert {
    condition     = !can(regex("WARNING", output.redirects_summary))
    error_message = "50 entries must fit in 80% of the edge code budget (NFR-3). Got: ${output.redirects_summary}."
  }
}
