# Publishes a Cloud Storage bucket to the shared BCC platform gateway. For a
# Cloud Run service, use ../gateway-backend.
#
# Runs in the APPLICATION's repo and project: a backend bucket must live in the
# same project as its GCS bucket, and creating one in the gateway project fails
# with "The Cloud Storage bucket '<name>' is not owned by the current project".
#
# The gateway builds its reference from the naming convention below rather than
# from an output, so the names must match and this must be applied BEFORE the
# gateway route merges. See ../README.md.

locals {
  # Staging is served by the PROD gateway, because staging environments live in
  # the application's production project. Keep in sync with `gateway_members` in
  # the gateway's locals.tf.
  tier = contains(["prod", "staging"], var.environment) ? "prod" : "sandbox"

  # Constants rather than an input: there is exactly one gateway per tier. Keep
  # in sync with ../gateway-backend.
  gateway_service_accounts = {
    prod    = "pr-platform-gateway-prod-gh@bcc-platform-prod.iam.gserviceaccount.com"
    sandbox = "pr-platform-gateway-sandbox-gh@bcc-platform-dev.iam.gserviceaccount.com"
  }

  # Must be unique across the organization: Cloud Load Balancing does not
  # disambiguate same-named resources across projects. The environment suffix is
  # required because prod and staging share one project. `bb-` distinguishes it
  # from a backend service's `bs-` in a URL map reference.
  backend_bucket_name = "bb-${var.app}-${var.component}-${var.environment}"
}

resource "google_compute_backend_bucket" "main" {
  name        = local.backend_bucket_name
  bucket_name = var.bucket
  enable_cdn  = var.enable_cdn
}

# Lets the gateway's URL map reference the backend bucket. Project-scoped
# because the provider has no per-backend-bucket IAM resource (checked against
# 6.x); the role only permits *referencing* backends. One grant covers backend
# services and buckets alike, so a second module instance must set
# grant_gateway_access = false.
resource "google_project_iam_member" "gateway_lb_user" {
  count = var.grant_gateway_access ? 1 : 0

  project = google_compute_backend_bucket.main.project
  role    = "roles/compute.loadBalancerServiceUser"
  member  = "serviceAccount:${local.gateway_service_accounts[local.tier]}"
}

# A backend bucket reads objects as this project's load balancer service agent,
# which is what lets the bucket be PRIVATE. That agent is created with the
# project's FIRST backend bucket, so this grant can fail on the first apply and
# succeed on the second: depends_on orders it but cannot wait for propagation.
data "google_project" "main" {
  count = var.grant_object_access ? 1 : 0
}

resource "google_storage_bucket_iam_member" "lb_object_viewer" {
  count = var.grant_object_access ? 1 : 0

  bucket = var.bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:service-${data.google_project.main[0].number}@https-lb.iam.gserviceaccount.com"

  depends_on = [google_compute_backend_bucket.main]
}
