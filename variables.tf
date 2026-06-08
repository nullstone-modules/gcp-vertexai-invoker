variable "app_metadata" {
  description = <<EOF
Nullstone automatically injects metadata from the app module into this module through this variable.
This variable is a reserved variable for capabilities.
EOF

  type    = map(string)
  default = {}
}

locals {
  service_account_email = var.app_metadata["service_account_email"]
}

variable "include_compute_tokens" {
  description = <<EOF
Include the `aiplatform.endpoints.computeTokens` permission, which powers server-side token
counting (e.g. Gemini's `countTokens`).

Set to `false` for Anthropic-only workloads, which count tokens client-side and never call
the server-side endpoint. When `false`, the custom role contains only
`aiplatform.endpoints.predict`.
EOF

  type    = bool
  default = true
}
