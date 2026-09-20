# One expect_failures case per structural rule, so that every check is proven
# able to fail (architecture rule 4, ADR-019). A failing precondition aborts
# `tofu plan`, so nothing is changed — which is what the rejection messages say.
#
# The fixtures are the DISCUSS examples, the same ones the offline site test
# uses in jeffbaileyblog/tests/regression/redirects/fixtures/.

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

run "v01_rejects_a_path_without_a_leading_slash" {
  command = plan
  variables {
    redirects = [{ from = "blog/2019/11/28/learning-terraform/", to = "/blog/2020/05/03/learn-terraform/" }]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v01_rejects_a_target_on_another_host" {
  command = plan
  variables {
    redirects = [{ from = "/blog/2019/11/28/learning-terraform/", to = "https://example.com/ssh/" }]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v01_rejects_a_query_string_inside_a_path" {
  command = plan
  variables {
    redirects = [{ from = "/blog/2019/11/28/learning-terraform/?utm_source=mastodon", to = "/blog/2020/05/03/learn-terraform/" }]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

# P-3: length() counts characters, not bytes, so a non-ASCII path would make the
# budget under-count. V-01's charset is what keeps the two equal.
run "v01_rejects_a_non_ascii_path" {
  command = plan
  variables {
    redirects = [{ from = "/blog/2019/11/28/apprendre-le-terraformé/", to = "/blog/2020/05/03/learn-terraform/" }]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v02_rejects_a_target_that_is_not_a_page" {
  command = plan
  variables {
    redirects = [{ from = "/blog/2019/11/28/learning-terraform/", to = "/blog/2020/05/03/learn-terraform" }]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v03_rejects_the_site_root_as_an_old_path" {
  command = plan
  variables {
    redirects = [{ from = "/", to = "/about/" }]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v04_rejects_a_well_known_path" {
  command = plan
  variables {
    redirects = [{ from = "/.well-known/webfinger", to = "/about/" }]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v04_rejects_the_oembed_prefix" {
  command = plan
  variables {
    redirects = [{ from = "/api/bsky-oembed", to = "/about/" }]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v05_rejects_the_same_old_path_in_two_spellings" {
  command = plan
  variables {
    redirects = [
      { from = "/blog/2025/12/30/fundamentals-of-software-maintainability", to = "/blog/2026/02/22/fundamentals-of-maintainability/" },
      { from = "/blog/2025/12/30/fundamentals-of-software-maintainability/", to = "/blog/2020/05/03/learn-terraform/" },
    ]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v06_rejects_a_self_redirect" {
  command = plan
  variables {
    redirects = [{ from = "/blog/2025/12/10/fundamental-data-structures/", to = "/blog/2025/12/10/fundamental-data-structures/" }]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v07_rejects_a_loop" {
  command = plan
  variables {
    redirects = [
      { from = "/blog/2025/12/10/fundamental-data-structures/", to = "/blog/2025/12/06/fundamentals-of-data-structures/" },
      { from = "/blog/2025/12/06/fundamentals-of-data-structures/", to = "/blog/2025/12/10/fundamental-data-structures/" },
    ]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v07_rejects_a_chain" {
  command = plan
  variables {
    redirects = [
      { from = "/blog/2025/12/10/fundamental-data-structures/", to = "/blog/2025/12/06/fundamentals-of-data-structures/" },
      { from = "/blog/2025/12/06/fundamentals-of-data-structures/", to = "/blog/2026/10/01/data-structures-guide/" },
    ]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "v08_rejects_a_list_over_the_edge_code_budget" {
  command = plan
  variables {
    redirects = [
      for i in range(120) : {
        from = format("/blog/2019/01/%02d/merged-away-post-number-%03d/", i % 28 + 1, i)
        to   = format("/blog/2026/01/%02d/surviving-guide-number-%03d/", i % 28 + 1, i)
      }
    ]
  }
  expect_failures = [aws_cloudfront_function.redirect_function]
}

run "the_function_name_must_be_a_legal_cloudfront_name" {
  command = plan
  variables {
    redirect_function_name = "redirect function"
  }
  expect_failures = [var.redirect_function_name]
}

# A clean list plans without any precondition firing. Without this case the
# expect_failures above would still pass if every rule rejected everything.
run "a_clean_list_is_accepted" {
  command = plan
  variables {
    redirects = [
      { from = "/blog/2019/11/23/gitgithub-com-permission-denied-publickey/", to = "/blog/2019/11/10/setting-ssh-key-permissions/" },
      { from = "/blog/2025/12/10/fundamental-data-structures/", to = "/blog/2025/12/06/fundamentals-of-data-structures/" },
      { from = "/blog/2025/12/12/fundamental-algorithmic-patterns/", to = "/blog/2025/12/04/fundamentals-of-algorithms/" },
      { from = "/blog/2025/12/30/fundamentals-of-software-maintainability", to = "/blog/2026/02/22/fundamentals-of-maintainability/" },
      { from = "/blog/2019/11/28/learning-terraform/", to = "/blog/2020/05/03/learn-terraform/" },
    ]
  }

  assert {
    condition     = can(regex("^5 redirects, ", output.redirects_summary))
    error_message = "A clean list must plan and report its count (AC-03.1). Got: ${output.redirects_summary}."
  }
}
