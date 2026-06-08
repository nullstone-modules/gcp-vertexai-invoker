locals {
  // GCP custom role IDs must match ^[a-zA-Z0-9_.]{3,64}$ -- hyphens are not allowed, so
  // sanitize the hyphenated resource_name into a valid identifier.
  custom_role_id = replace(local.resource_name, "-", "_")

  // The two permissions an inference workload actually uses. computeTokens is optional
  // (Anthropic-only workloads count tokens client-side) and gated by var.include_compute_tokens.
  invoker_permissions = concat(
    ["aiplatform.endpoints.predict"],
    var.include_compute_tokens ? ["aiplatform.endpoints.computeTokens"] : [],
  )
}

// Project-scoped custom role containing only the inference permissions -- deliberately NOT
// roles/aiplatform.user, which would also allow training jobs, deployments, and batch prediction.
resource "google_project_iam_custom_role" "invoker" {
  role_id     = local.custom_role_id
  title       = "Vertex AI Invoker for ${local.block_name}"
  description = "Least-privilege role to invoke Vertex AI models (predict + token counting only)."
  stage       = "GA"

  permissions = local.invoker_permissions
}

// Bind the custom role to the app's runtime service account.
resource "google_project_iam_member" "invoker" {
  project = local.project_id
  role    = google_project_iam_custom_role.invoker.id
  member  = "serviceAccount:${local.service_account_email}"
}
