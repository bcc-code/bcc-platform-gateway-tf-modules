variable "app" {
  type        = string
  description = "Application slug. Must match the `app` field in the gateway's routes/<app>.yaml."
}

variable "component" {
  type        = string
  description = "Component slug. Must match the backend key in routes/<app>.yaml (e.g. \"api\")."
}

variable "environment" {
  type        = string
  description = "Application environment: dev, sandbox, staging or prod."

  validation {
    condition     = contains(["dev", "sandbox", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, sandbox, staging, prod."
  }
}

variable "cloud_run_service" {
  type        = string
  description = <<-DESC
    Name of the Cloud Run service to route to. Must be in this project and
    region. It need not exist yet — a serverless NEG holds only a name.
  DESC
}

variable "region" {
  type        = string
  description = <<-DESC
    Region of the Cloud Run service. A regional NEG does not inherit the
    provider's region, and one pointing at the wrong region resolves to nothing
    at request time rather than failing at apply.
  DESC
}

variable "grant_gateway_access" {
  type        = bool
  default     = true
  description = <<-DESC
    Grant the gateway's service account roles/compute.loadBalancerServiceUser on
    this project, which is what lets its URL map reference this backend.

    Set false on every instance but one: the grant is project-scoped, and a
    second instance managing the identical binding removes it from under the
    first when destroyed.
  DESC
}

variable "security_policy" {
  type        = string
  default     = null
  description = "Self-link of a Cloud Armor security policy. Must be in this project."
}

variable "enable_cdn" {
  type        = bool
  default     = false
  description = "Enable Cloud CDN on this backend."
}

variable "custom_request_headers" {
  type        = list(string)
  default     = []
  description = "Extra request headers to add. Do not rewrite Host: Cloud Run needs the original host to match its custom domain."
}
