# Publishes Compute Engine VMs to the shared BCC platform gateway. For a Cloud
# Run service, use ../gateway-backend; for a GCS bucket, ../gateway-backend-bucket.
#
# Runs in the APPLICATION's repo and project: a backend service can only
# reference instance groups and health checks in its own project.
#
# The gateway builds its reference from the naming convention below rather than
# from an output, so the names must match and this must be applied BEFORE the
# gateway route merges. See ../README.md.

locals {
  # Staging is served by the PROD gateway, because staging environments live in
  # the application's production project. Keep in sync with `gateway_members` in
  # locals.tf in bcc-code/bcc-platform-gateway.
  tier = contains(["prod", "staging"], var.environment) ? "prod" : "sandbox"

  # Constants rather than an input: there is exactly one gateway per tier. Keep
  # in sync with ../gateway-backend and ../gateway-backend-bucket.
  gateway_service_accounts = {
    prod    = "pr-platform-gateway-prod-gh@bcc-platform-prod.iam.gserviceaccount.com"
    sandbox = "pr-platform-gateway-sandbox-gh@bcc-platform-dev.iam.gserviceaccount.com"
  }

  # Must be unique across the organization: Cloud Load Balancing does not
  # disambiguate same-named resources across projects. The environment suffix is
  # required because prod and staging share one project. Same `bs-` prefix as
  # ../gateway-backend: to the URL map both are backend services.
  service_name      = "bs-${var.app}-${var.component}-${var.environment}"
  health_check_name = "hc-${var.app}-${var.component}-${var.environment}"
  firewall_name     = "fw-${var.app}-${var.component}-${var.environment}-gateway"

  # Source ranges of Google Front Ends. A global external Application Load
  # Balancer both health-checks AND proxies traffic from these, so one rule
  # covers both.
  gfe_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}

resource "google_compute_health_check" "main" {
  name = local.health_check_name

  check_interval_sec  = var.health_check.check_interval_sec
  timeout_sec         = var.health_check.timeout_sec
  healthy_threshold   = var.health_check.healthy_threshold
  unhealthy_threshold = var.health_check.unhealthy_threshold

  # USE_SERVING_PORT probes the backend service's named port, so the port is
  # stated once, on the instance groups, and cannot drift from the traffic port.
  dynamic "http_health_check" {
    for_each = var.protocol == "HTTP" ? [1] : []
    content {
      port_specification = "USE_SERVING_PORT"
      request_path       = var.health_check.request_path
    }
  }

  dynamic "https_health_check" {
    for_each = var.protocol == "HTTPS" ? [1] : []
    content {
      port_specification = "USE_SERVING_PORT"
      request_path       = var.health_check.request_path
    }
  }

  dynamic "http2_health_check" {
    for_each = var.protocol == "HTTP2" ? [1] : []
    content {
      port_specification = "USE_SERVING_PORT"
      request_path       = var.health_check.request_path
    }
  }
}

resource "google_compute_backend_service" "main" {
  name = local.service_name

  # Must match the gateway's forwarding rules, and it is the only scheme that
  # supports cross-project service referencing.
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = var.protocol
  port_name             = var.port_name
  timeout_sec           = var.timeout_sec
  health_checks         = [google_compute_health_check.main.id]

  enable_cdn      = var.enable_cdn
  security_policy = var.security_policy

  custom_request_headers  = var.custom_request_headers
  custom_response_headers = var.custom_response_headers

  dynamic "backend" {
    for_each = var.instance_groups
    content {
      group           = backend.value
      balancing_mode  = "UTILIZATION"
      capacity_scaler = 1
    }
  }

  log_config {
    enable      = true
    sample_rate = 1
  }
}

# Without this the backends never turn healthy and the gateway returns 502s:
# the default VPC rules admit nothing from the Google Front Ends.
resource "google_compute_firewall" "gateway" {
  count = var.firewall == null ? 0 : 1

  name      = local.firewall_name
  project   = var.firewall.project
  network   = var.firewall.network
  direction = "INGRESS"

  source_ranges           = local.gfe_ranges
  target_tags             = var.firewall.target_tags
  target_service_accounts = var.firewall.target_service_accounts

  allow {
    protocol = "tcp"
    ports    = [tostring(var.port)]
  }

  lifecycle {
    precondition {
      condition     = (var.firewall.target_tags == null) != (var.firewall.target_service_accounts == null)
      error_message = "firewall needs exactly one of target_tags or target_service_accounts: without either, the rule opens the port on every VM in the network."
    }
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
