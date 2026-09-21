# Terraform Module: AWS CloudFront Websites

> Terraform Module for managing AWS CloudFront Websites

## Table of Contents

- [Terraform Module: AWS CloudFront Websites](#terraform-module-aws-cloudfront-websites)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Requirements](#requirements)
  - [Dependencies](#dependencies)
  - [Usage](#usage)
    - [Inputs](#inputs)
    - [Edge redirects](#edge-redirects)
    - [Outputs](#outputs)
  - [Author Information](#author-information)
  - [License](#license)

## Overview

![Terraform Module: AWS CloudFront Websites](https://raw.githubusercontent.com/jeffabailey/terraform-aws-cloudfront-website/master/overview.png "Terraform Module: AWS CloudFront Websites")

## Requirements

This module requires Terraform version `0.13.0` or newer.

## Dependencies

This module depends on a correctly configured [AWS Provider](https://www.terraform.io/docs/providers/aws/index.html) in your Terraform codebase.

## Usage

Add the module to your Terraform resources like so:

```hcl
module "cloudfront_website" {
  providers = {
    aws.distribution = aws
    // NOTE: ACM Certificates for usage with CloudFront need to be created in the `us-east-1` region, see https://amzn.to/2TW2J16
    aws.global = aws
  }

  source  = "jeffabailey/cloudfront-website/aws"
  version = "0.6.0"

  domain_name = "example.com"
  alternate_domain_names = [
    "www.example.com"
  ]

  s3_bucket_name      = "example-website"
  s3_use_prefix       = false
  s3_policy           = ""
  s3_use_default_tags = true
  s3_tags = {
    website = "https://example.com/"
  }

  s3_force_destroy = false
  s3_create_readme = false

  acm_use_default_tags = true
  acm_tags = {
    website = "https://example.com/"
  }

  route53_zone_id = "Z3P5QSUBK4POTI"
}
```

Then, fetch the module from the [Terraform Registry](https://registry.terraform.io/modules/jeffabailey/cloudfront-website) using `terraform get`.

### Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| domain_name | Domain name of website | `string` | n/a |
| route53_zone_id | ID of Route 53 Zone to use for Certificate Validation | `string` | n/a |
| s3_bucket_name | Name of S3 Bucket | `string` | n/a |
| acm_enable_certificate_transparency_log | Toggle to enable a Certificate Transparency Log | `bool` | `true` |
| acm_tags | Mapping of Tags of ACM Certificate | `map(string)` | `{}` |
| acm_use_default_tags | Toggle to enable creation of default tags for ACM Certificate, containing Terraform Workspace identifier | `bool` | `true` |
| alternate_domain_names | Alternate Domain Names of Website | `list(string)` | `[]` |
| cloudfront_comment | Comment for CloudFront Distribution | `string` | `"Terraform-managed resource"` |
| cloudfront_default_cache_behavior | Default cache behavior for CloudFront Distribution | `map` | `{}` |
| cloudfront_default_root_object | Default Object to return for CloudFront Distribution | `string` | `"index.html"` |
| cloudfront_enabled | Toggle to enable CloudFront Distribution | `bool` | `true` |
| cloudfront_http_version | HTTP version for CloudFront Distribution | `string` | `"http2"` |
| cloudfront_is_ipv6_enabled | Toggle to enable IPv6 support for CloudFront Distribution | `bool` | `true` |
| cloudfront_minimum_protocol_version | Minimum version of SSL protocol to support for this CloudFront Distribution | `string` | `"TLSv1.1_2016"` |
| cloudfront_origin_access_identity_comment | Comment for CloudFront Origin Access Identity | `string` | `""` |
| cloudfront_price_class | Price class for CloudFront Distribution | `string` | `"PriceClass_100"` |
| cloudfront_ssl_support_method | HTTPs request serving method for CloudFront Distribution | `string` | `"sni-only"` |
| cloudfront_tags | Mapping of Tags of CloudFront Distribution | `map(string)` | `{}` |
| cloudfront_use_default_tags | Toggle to enable creation of default tags for CloudFront Distribution, containing Terraform Workspace identifier | `bool` | `true` |
| s3_create_readme | Toggle creation of `README.md` in root of S3 Bucket | `bool` | `false` |
| s3_force_destroy | Toggle to enable force-destruction of S3 Bucket | `bool` | `false` |
| s3_policy | Policy (JSON) Document of S3 Bucket | `string` | `null` |
| s3_tags | Mapping of Tags of S3 Bucket | `map(string)` | `{}` |
| s3_use_default_tags | Toggle to enable creation of default tags for S3 Bucket, containing Terraform Workspace identifier | `bool` | `true` |
| s3_use_prefix | Toggle to use randomly-generated Prefix for Bucket Name | `bool` | `false` |
| security_headers | Optional structured security headers; module generates an `aws_cloudfront_response_headers_policy` from them and attaches to the distribution. Object fields: `content_security_policy` (string), `strict_transport_security` (object: `max_age_sec`, `include_subdomains`, `preload`), `content_type_options_nosniff` (bool), `referrer_policy` (string), `frame_option` (`DENY` or `SAMEORIGIN`). Each is emitted only when set. Mutually exclusive with `response_headers_policy_id`. | `object` | `null` |
| response_headers_policy_id | Optional pre-built `aws_cloudfront_response_headers_policy` id (e.g., AWS managed policy or a shared cross-distribution policy). Attached to the distribution directly. Mutually exclusive with `security_headers`. | `string` | `null` |
| redirects | Edge 301 redirects, rendered into the viewer-request function as an exact-match lookup table. See [Edge redirects](#edge-redirects). | `list(object({ from = string, to = string }))` | `[]` |
| redirect_function_name | Name of the viewer-request CloudFront Function. Unique per AWS account. Null derives `<domain>-redirect`. | `string` | `null` |
| bsky_oembed_function_name | Name of the Bluesky oEmbed CloudFront Function. Null derives `<domain>-bsky-oembed`. | `string` | `null` |

#### Response-headers policy (ADR-MCEJU-003)

Two opt-in variables let consumers attach an `aws_cloudfront_response_headers_policy` without writing the boilerplate themselves, while keeping an escape hatch for callers who already maintain their own policies.

```hcl
# Structured — module builds the policy
module "cloudfront_website" {
  source = "..."
  # ...
  security_headers = {
    content_security_policy = "frame-src https://element.example.com"

    # All optional; each header is emitted only when set.
    strict_transport_security = {
      max_age_sec        = 31536000
      include_subdomains = true  # only when every subdomain serves HTTPS
      preload            = false # the preload list is slow to undo
    }
    content_type_options_nosniff = true
    referrer_policy              = "strict-origin-when-cross-origin"
    frame_option                 = "SAMEORIGIN" # or DENY
  }
}

# Pass-through — caller supplies a pre-built policy id
module "cloudfront_website" {
  source = "..."
  # ...
  response_headers_policy_id = aws_cloudfront_response_headers_policy.shared.id
}
```

Setting both is a plan-time error: the precondition on `terraform_data.validate_security_headers_exclusive` names both variables in the message. Neither variable set preserves the module's pre-existing behavior (no response-headers policy attached).

### Edge redirects

`var.redirects` turns a list of merged-away pages into real HTTP 301s, answered by the existing viewer-request CloudFront Function before the cache and the origin are reached. The default empty list renders the same code as before, so a consumer that sets nothing sees no redirect behavior at all.

```hcl
module "cloudfront_website" {
  source = "..."
  # ...
  domain_name = "example.com"

  redirects = [
    { from = "/blog/2019/11/23/old-post/", to = "/blog/2019/11/10/surviving-post/" },
  ]
}

output "redirects" {
  value = module.cloudfront_website.redirects_summary
}
```

Keeping the list in a file beside the root configuration, so that adding a redirect is a one-line data change, is the pattern this was built for:

```hcl
redirects = [
  for entry in yamldecode(file("${path.module}/redirects.yaml")).redirects :
  { from = entry.from, to = entry.to }
]
```

The module never reads a consumer file itself. Projecting each entry explicitly means a misspelled key fails the plan instead of being dropped.

**What the edge does.** The path is normalized — a trailing `/index.html` is dropped, otherwise one trailing `/` — and looked up in a JSON table keyed the same way, so the `/old-post/`, `/old-post` and `/old-post/index.html` spellings all reach the target in one hop. Matching is exact and case-sensitive. A hit answers:

- `301 Moved Permanently`
- `location: https://<var.domain_name><to>`, plus `?` and the request's query string when there is one. The host always comes from the module input, never from the request, so a list entry can never open a redirect to a foreign host.
- `cache-control: max-age=31536000`

A miss is passed through to the origin unchanged.

**One year of browser cache.** A returning visitor whose browser cached a wrong redirect follows it for up to a year without asking the edge again, and no later edit reaches that browser. So: run the checks before every apply, and **correct a wrong entry by changing its `to`, never by deleting it**. Re-pointing serves the corrected 301 immediately and keeps the signal consistent for search engines; deleting brings the old page back for crawlers while cached browsers still go to the wrong target.

**Rules checked at plan time.** These are `lifecycle` preconditions on the function, so they run during `tofu plan`, before any AWS call. A failure aborts the plan and changes nothing. Each message names its rule, the offending entries, and the fix.

| Rule | What it rejects |
|------|-----------------|
| V-01 | A path that does not start with `/`, uses characters outside `A-Z a-z 0-9 . _ ~ % / -`, or contains `//`, `?`, `#`, or whitespace. This is also what keeps a target on the same site, and what keeps characters equal to bytes for the budget. |
| V-02 | A target that neither ends in `/` nor names a file, which the origin would bounce a second time |
| V-03 | `/` as an old path |
| V-04 | An old path under `/.well-known/` or under the Bluesky oEmbed prefix — identity and discovery paths are never redirected by a content list |
| V-05 | The same old path listed twice, in any spelling. The message names both targets. |
| V-06 | An entry that points at itself |
| V-07 | A target that is itself an old path on the list (a chain), or a pair that points at each other (a loop). Chain messages suggest the final target. |
| V-08 | A rendered function over 10,240 bytes, the CloudFront Functions limit |
| V-10 | A path the module answers itself that no reserved prefix covers. The validator checks the module, not just the list. |

**Budget.** `redirects_summary` reports `"<N> redirects, <B> of 10240 bytes (<P>%)"`, and appends `"; WARNING: <P>% of the edge code budget used, <R> bytes remain"` at 80% of the limit. Re-export it from the root to see the line in the plan's *Changes to Outputs*. An entry costs about `len(from) + len(to) + 6` bytes, so roughly 60 to 70 entries fit inside the warning threshold. Past that, the scale path is a CloudFront KeyValueStore, which needs a newer AWS provider than this module requires.

**Function name and shared accounts.** CloudFront Function names are unique per AWS account, and the name forces replacement. Both function names now derive from `domain_name` when left null, giving `example-com-redirect` and `example-com-bsky-oembed`. That default exists because the previous one did not: every consumer took the literal `redirect-function`, so every consumer was configured to manage the same function. Two of them did, and the second state held stale code that an apply would have written over the first site's live redirects. Set `redirect_function_name` or `bsky_oembed_function_name` only to pin a legacy name a live distribution already points at. The resource is `create_before_destroy`, so a rename creates and associates the new function before the old one is deleted, and the distribution never points at a deleted function. Never bundle a rename with a list change: plan and apply it on its own.

**Verifying after apply.**

```console
$ curl -sI https://example.com/blog/2019/11/23/old-post/
HTTP/2 301
location: https://example.com/blog/2019/11/10/surviving-post/
cache-control: max-age=31536000
x-cache: FunctionGeneratedResponse from cloudfront
```

Check the slash-less and `/index.html` spellings and one query string too, then confirm `tofu plan` reports no changes.

### Outputs

| Name | Description |
|------|-------------|
| bucket_arn | ARN of the S3 Bucket |
| bucket_hosted_zone_id | Route 53 Hosted Zone ID of the S3 Bucket |
| bucket_id | Identifier of the S3 Bucket |
| certificate_arn | ARN of the ACM Certificate |
| certificate_domain_name | Domain name(s) of the ACM Certificate |
| certificate_id | Identifier of the ACM Certificate |
| distribution_active_trusted_signers | Key Pair IDs that are able to sign private URLs for the CloudFront Distribution |
| distribution_arn | ARN of the CloudFront Distribution |
| distribution_domain_name | Domain Name of the CloudFront Distribution |
| distribution_etag | Identifier of Current Version of the CloudFront Distribution |
| distribution_hosted_zone_id | Route 53 Zone ID for the CloudFront Distribution |
| distribution_id | Identifier for the CloudFront Distribution |
| distribution_in_progress_validation_batches | Number of invalidation batches currently in progress for the CloudFront Distribution |
| distribution_last_modified_time | Date and time of last modification for the CloudFront Distribution |
| distribution_status | Status of the CloudFront Distribution |
| origin_access_identity_etag | Identifier of current version of the Origin Access Identity |
| redirects_summary | Number of edge redirects published, and the rendered function size against the 10,240-byte limit. Carries a `WARNING` at 80% of the budget. |
| origin_access_identity_iam_arn | ARN of the Origin Access Identity |
| origin_access_identity_id | Identifier of the CloudFront Distribution |
| origin_access_identity_path | Full path of the Origin Access Identity |
| origin_access_identity_s3_canonical_user_id | Canonical S3 User ID of the Origin Access Identity |
| route53_record_fqdn | Name of the Route 53 Record FQDN |
| route53_record_names | Name of the Route 53 Record Name(s) |

## Author Information

This module is maintained by the contributors listed on [GitHub](https://github.com/jeffabailey/terraform-aws-cloudfront-website/graphs/contributors).

Development of this module was sponsored by [Operate Happy](https://github.com/jeffabailey).

## License

Licensed under the Apache License, Version 2.0 (the "License").

You may obtain a copy of the License at [apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0).

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an _"AS IS"_ basis, without WARRANTIES or conditions of any kind, either express or implied.

See the License for the specific language governing permissions and limitations under the License.
