module "versioning_example" {
  source  = "jeffabailey/s3-bucket/aws"
  version = "1.2.0"

  name = "oh-demos-versioning-example"

  versioning = {
    enabled    = true
    mfa_delete = false
  }
}
