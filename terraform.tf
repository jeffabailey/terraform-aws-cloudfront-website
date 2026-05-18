terraform {
  # >= 1.4.0 required for the built-in `terraform_data` resource used by the
  # response-headers-policy mutual-exclusion precondition (ADR-MCEJU-003).
  # Earlier versions can backport via `null_resource` from hashicorp/null.
  required_version = ">= 1.4.0"

  required_providers {
    aws = ">= 3.4.0"
  }
}
