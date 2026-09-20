## 0.7.0 (2026-09-19)

### BREAKING

* **Removed the Bridgy Fed redirects from `aws_cloudfront_function.redirect_function`.** `/.well-known/host-meta*` and `/.well-known/webfinger*` no longer answer a 302 to `https://fed.brid.gy`; they now fall through to the S3 origin, which answers 404. The removed rule built its Location from `request.uri`, which drops the query string, so a webfinger lookup through it could not identify an account. Any consumer whose state already holds the function sees exactly one in-place update that deletes the two blocks. `/.well-known/atproto-did` is unchanged.

### Features

* **`redirects`** (`list(object({ from = string, to = string }))`, default `[]`): edge 301 redirects for merged-away pages, rendered into the existing viewer-request function as an exact-match lookup table. All three spellings of an old path (`/p/`, `/p`, `/p/index.html`) reach the target in one hop; the query string is preserved; the Location is absolute and built from `var.domain_name`; generated 301s carry `cache-control: max-age=31536000`. With the default empty list the rendered code is byte-identical to 0.6.2's minus the Bridgy blocks. See "Edge redirects" in the README.
* **`redirect_function_name`** (`string`, default `"redirect-function"`): the function name is now configurable, so a second site in the same AWS account can avoid the `FunctionAlreadyExists` collision. The default is the legacy name, so no consumer is renamed. The resource gained `create_before_destroy`, which makes a rename safe: the new function is created and associated before the old one is deleted.
* **`redirects_summary`** output: `"<N> redirects, <B> of 10240 bytes (<P>%)"`, with a `WARNING` and the remaining headroom appended at 80% of the CloudFront Functions code limit.
* **Plan-time validation** of the redirect list, as `lifecycle` preconditions on the function: malformed or off-site paths, targets that are not pages, `/` as an old path, reserved identity prefixes, duplicates, self-redirects, chains and loops, and the 10,240-byte limit. A failure aborts `tofu plan` before any AWS call, so nothing is changed. No new resource, no `required_version` bump.
* **`tofu test` suite** under `tests/`: a golden render for the empty list, the one-code-string contract, and one `expect_failures` case per validation rule.

## <small>0.6.2 (2020-10-07)</small>

* Remove provider blocks (#6) ([183b640](https://github.com/jeffabailey/terraform-aws-cloudfront-website/commit/183b640)), closes [#6](https://github.com/jeffabailey/terraform-aws-cloudfront-website/issues/6)

# 0.6.1 (2020-09-18)

* Linting (#5) ([3c7c026](https://github.com/jeffabailey/terraform-aws-cloudfront-website/commit/3c7c026)), closes [#5](https://github.com/jeffabailey/terraform-aws-cloudfront-website/issues/5)

## 0.6.0 (2020-09-15)

* Updates provider version (#4) ([1b373b5](https://github.com/jeffabailey/terraform-aws-cloudfront-website/commit/1b373b5)), closes [#4](https://github.com/jeffabailey/terraform-aws-cloudfront-website/issues/4)

## 0.5.1 (2020-06-24)

* updates ACM module from `1.0.0` to `1.0.1` ([d2b5b21](https://github.com/jeffabailey/terraform-aws-cloudfront-website/commit/d2b5b21))
* updates README ([e49787e](https://github.com/jeffabailey/terraform-aws-cloudfront-website/commit/e49787e))

## 0.5.0 (2020-06-19)

* adds base files ([e81abd5](https://github.com/jeffabailey/terraform-aws-cloudfront-website/commit/e81abd5))
* Prep for release (#2) ([7073b49](https://github.com/jeffabailey/terraform-aws-cloudfront-website/commit/7073b49)), closes [#2](https://github.com/jeffabailey/terraform-aws-cloudfront-website/issues/2)
