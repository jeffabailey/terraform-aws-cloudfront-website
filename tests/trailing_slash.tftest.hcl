variables {
  domain_name     = "example.test"
  s3_bucket_name  = "example-bucket"
  route53_zone_id = "Z00000000000000000000"
}
run "off_by_default_leaves_the_function_unchanged" {
  command = plan
  assert {
    condition     = !strcontains(aws_cloudfront_function.redirect_function.code, "lastIndexOf")
    error_message = "the trailing-slash block must not render unless a consumer asks for it"
  }
}
run "on_renders_a_301_for_a_directory_url" {
  command = plan
  variables { canonical_trailing_slash = true }
  assert {
    condition     = strcontains(aws_cloudfront_function.redirect_function.code, "uri.lastIndexOf(\".\") <= uri.lastIndexOf(\"/\")")
    error_message = "expected the directory test"
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.redirect_function.code, "uri.indexOf(\"/.well-known/\") !== 0")
    error_message = "well-known paths must be excluded"
  }
  assert {
    condition     = strcontains(aws_cloudfront_function.redirect_function.code, "statusCode: 301")
    error_message = "expected a 301"
  }
}
