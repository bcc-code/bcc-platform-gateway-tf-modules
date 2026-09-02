variable "app" {
  type        = string
  description = "Application slug. Must match the `app` field in the gateway's routes/<app>.yaml."
}

variable "component" {
  type        = string
  description = "Component slug. Must match the backend key in routes/<app>.yaml (e.g. \"ui\")."
}

variable "environment" {
  type        = string
  description = "Application environment: dev, sandbox, staging or prod."

  validation {
    condition     = contains(["dev", "sandbox", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, sandbox, staging, prod."
  }
}

variable "bucket" {
  type        = string
  description = "Name of the GCS bucket to serve. Must be in this project — a backend bucket cannot point at a bucket in another one."
}

variable "grant_gateway_access" {
  type        = bool
  default     = true
  description = <<-DESC
    Grant the gateway's service account roles/compute.loadBalancerServiceUser on
    this project, which is what lets its URL map reference this backend bucket.

    Set false on every instance but one: the grant is project-scoped, and a
    second instance managing the identical binding removes it from under the
    first when destroyed.
  DESC
}

variable "grant_object_access" {
  type        = bool
  default     = false
  description = <<-DESC
    Grant this project's load balancer service agent
    (service-<project number>@https-lb.iam.gserviceaccount.com)
    roles/storage.objectViewer, which is what lets the bucket be PRIVATE.

    Leave false while an old load balancer still reaches the bucket over the
    public internet: that path needs allUsers, and removing it first is an
    outage.
  DESC
}

variable "enable_cdn" {
  type        = bool
  default     = false
  description = "Enable Cloud CDN on this backend bucket."
}
