data "google_client_config" "this" {}

locals {
  project_id = data.google_client_config.this.project
}
