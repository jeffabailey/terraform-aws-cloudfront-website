module "logging_example_target" {
  source  = "jeffabailey/s3-bucket/aws"
  version = "1.2.0"
  name    = "oh-demos-logging-example-target"
  acl     = "log-delivery-write"
}

module "logging_example" {
  source  = "jeffabailey/s3-bucket/aws"
  version = "1.2.0"

  name = "oh-demos-logging-example"

  logging = {
    target_bucket = module.logging-example-target.id
    target_prefix = "logs"
  }
}
