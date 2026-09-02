output "backend_service_name" {
  description = "Name the gateway's route registry expects. Changing it needs a coordinated gateway PR."
  value       = google_compute_backend_service.main.name
}

output "backend_service_id" {
  description = "Self-link of the backend service, for debugging. The gateway builds its reference from the naming convention instead."
  value       = google_compute_backend_service.main.id
}

output "gateway_tier" {
  description = "Which gateway serves this environment: \"prod\" (prod, staging) or \"sandbox\" (dev, sandbox)."
  value       = local.tier
}

output "route_registry_snippet" {
  description = "Paste-ready fragment for the gateway's routes/<app>.yaml."
  value       = <<-YAML
    # routes/${var.app}.yaml
    backends:
      ${var.component}:
        type: cloud_run
    # environments.${var.environment}.project_id must be ${google_compute_backend_service.main.project}
  YAML
}
