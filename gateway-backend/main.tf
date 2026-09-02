# Publishes a Cloud Run service to the shared BCC platform gateway.
#
# Runs in the APPLICATION's repo and project: a serverless NEG must live in the
# same project as its Cloud Run service, and a backend service can only
# reference NEGs in its own project.
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
  # in sync with ../gateway-backend-bucket.
  gateway_service_accounts = {
    prod    = "pr-platform-gateway-prod-gh@bcc-platform-prod.iam.gserviceaccount.com"
    sandbox = "pr-platform-gateway-sandbox-gh@bcc-platform-dev.iam.gserviceaccount.com"
  }

  # Must be unique across the organization: Cloud Load Balancing does not
  # disambiguate same-named resources across projects. The environment suffix is
  # required because prod and staging share one project.
  service_name = "bs-${var.app}-${var.component}-${var.environment}"
  neg_name     = "neg-${var.app}-${var.component}-${var.environment}"
}

resource "google_compute_region_network_endpoint_group" "main" {
  name                  = local.neg_name
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.cloud_run_service
  }
}

resource "google_compute_backend_service" "main" {
  name = local.service_name

  # Must match the gateway's forwarding rules, and it is the only scheme that
  # supports cross-project service referencing.
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"

  # timeout_sec is unset deliberately: a serverless NEG backend rejects it
  # ("Timeout sec is not supported for a backend service with Serverless
  # network endpoint groups"). Cloud Run's own request timeout applies.

  enable_cdn      = var.enable_cdn
  security_policy = var.security_policy

  custom_request_headers = var.custom_request_headers

  backend {
    group = google_compute_region_network_endpoint_group.main.id
    # balancing_mode and capacity_scaler are invalid for serverless NEGs.
  }

  log_config {
    enable      = true
    sample_rate = 1
  }
}

# Lets the gateway's URL map reference the backend service. Project-scoped
# because the provider has no per-backend-service IAM resource (checked against
# 6.x); the role only permits *referencing* backends. One grant covers the
# project, so a second module instance must set grant_gateway_access = false.
resource "google_project_iam_member" "gateway_lb_user" {
  count = var.grant_gateway_access ? 1 : 0

  project = google_compute_backend_service.main.project
  role    = "roles/compute.loadBalancerServiceUser"
  member  = "serviceAccount:${local.gateway_service_accounts[local.tier]}"
}
