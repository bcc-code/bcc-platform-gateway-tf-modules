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

variable "instance_groups" {
  type        = list(string)
  description = <<-DESC
    Self-links of the instance groups to route to: a managed group's
    `instance_group` attribute, or an unmanaged group's `self_link` for
    standalone VMs. Must be in this project, and each must declare a named port
    called `port_name`.
  DESC

  validation {
    condition     = length(var.instance_groups) > 0
    error_message = "instance_groups must not be empty: a backend service with no backends serves only 502s."
  }
}

variable "port_name" {
  type        = string
  default     = "http"
  description = "Named port the backend service sends traffic to. Every group in instance_groups must declare it."
}

variable "port" {
  type        = number
  default     = 80
  description = "Port that `port_name` maps to on the VMs. Used only for the rule `firewall` creates."
}

variable "protocol" {
  type        = string
  default     = "HTTP"
  description = <<-DESC
    Protocol from the gateway to the VMs: HTTP, HTTPS or HTTP2. The health check
    uses the same one. With HTTPS the load balancer does not validate the VM's
    certificate, so a self-signed one is fine.
  DESC

  validation {
    condition     = contains(["HTTP", "HTTPS", "HTTP2"], var.protocol)
    error_message = "protocol must be one of: HTTP, HTTPS, HTTP2."
  }
}

variable "health_check" {
  type = object({
    request_path        = optional(string, "/")
    check_interval_sec  = optional(number, 5)
    timeout_sec         = optional(number, 5)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 2)
  })
  default     = {}
  description = "Health check settings. Any 200 response from request_path counts as healthy; redirects and auth challenges do not."

  validation {
    condition     = var.health_check.timeout_sec <= var.health_check.check_interval_sec
    error_message = "health_check.timeout_sec must not exceed check_interval_sec."
  }
}

variable "timeout_sec" {
  type        = number
  default     = 30
  description = "How long the gateway waits for a full response from a VM. Raise it for long-polling or large uploads; WebSockets are capped by it too."
}

variable "firewall" {
  type = object({
    network                 = string
    project                 = optional(string)
    target_tags             = optional(list(string))
    target_service_accounts = optional(list(string))
  })
  default     = null
  description = <<-DESC
    Create a firewall rule admitting the Google Front Ends (health checks and
    proxied traffic) to `port` on the VMs. Leave null only if an existing rule
    already does: without one, every backend stays unhealthy.

    Set exactly one of target_tags or target_service_accounts. With a Shared
    VPC, set project to the host project, which owns the network's rules.
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
  description = "Extra request headers to add, as \"Name: value\" (e.g. \"X-Client-Region: {client_region}\")."

  validation {
    condition     = alltrue([for h in var.custom_request_headers : can(regex("^[!#$%&'*+.^_`|~0-9A-Za-z-]+:", h))])
    error_message = "Each entry in custom_request_headers must be \"Name: value\"."
  }
}

variable "custom_response_headers" {
  type        = list(string)
  default     = []
  description = "Extra response headers to add, as \"Name: value\" (e.g. \"X-Frame-Options: DENY\")."

  validation {
    condition     = alltrue([for h in var.custom_response_headers : can(regex("^[!#$%&'*+.^_`|~0-9A-Za-z-]+:", h))])
    error_message = "Each entry in custom_response_headers must be \"Name: value\"."
  }
}
