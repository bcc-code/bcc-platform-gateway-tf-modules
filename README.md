# Publishing a backend to the shared gateway

Three modules, all applied **in your own repo and project**, never in the
gateway's:

| What you want routed                   | Module                                           |
| -------------------------------------- | ------------------------------------------------ |
| a Cloud Run service                    | [gateway-backend](gateway-backend)               |
| a GCS bucket (static site, SPA bundle) | [gateway-backend-bucket](gateway-backend-bucket) |
| Compute Engine VMs                     | [gateway-backend-vm](gateway-backend-vm)         |

None of these resources can be created by the gateway: a serverless NEG must sit
in the same project as its Cloud Run service, a backend bucket in the same
project as its GCS bucket, and a backend service in the same project as its
instance groups and health check. The gateway references what you create, cross-project, by
name.

## Cloud Run

```hcl
module "gateway_backend" {
  source = "github.com/bcc-code/bcc-platform-gateway-tf-modules//gateway-backend?ref=main"

  app         = "members"
  component   = "api"
  environment = local.props.app_environment   # dev | sandbox | staging | prod

  cloud_run_service = google_cloud_run_v2_service.api.name
  region            = google_cloud_run_v2_service.api.location
}
```

The service need not exist yet — a serverless NEG holds only a name — but
`region` must be the one it runs in: a regional NEG does not inherit the
provider's region, and one created in the wrong region resolves to nothing at
request time instead of failing at apply.

Set ingress so the service is reachable only through the gateway:

```hcl
resource "google_cloud_run_v2_service" "api" {
  # ...
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
}
```

If your repo is deployed by `bcc-platform-deploy`, `local.props` is the usual

```hcl
locals {
  props = merge(jsondecode(var.props), jsondecode(var.deployment_props))
}
```

and `app_environment` is already one of the four values the module accepts.

## GCS bucket

```hcl
module "gateway_backend_ui" {
  source = "github.com/bcc-code/bcc-platform-gateway-tf-modules//gateway-backend-bucket?ref=main"

  app         = "members"
  component   = "ui"
  environment = local.props.app_environment

  bucket = google_storage_bucket.ui.name
}
```

The bucket must be in this same project, and its objects readable at request
time: either publicly, or — once nothing else serves the bucket over the public
internet — privately, with `grant_object_access = true`, which grants your
project's load balancer service agent `roles/storage.objectViewer`. Where the
site lives _inside_ the bucket is a route concern: a bundle under `/ui/` is
handled by `path_prefix_rewrite: "/ui/"` on the gateway route.

## Compute Engine VMs

The module takes instance groups, not VMs. A managed instance group passes its
`instance_group`; standalone VMs go in an unmanaged group of your own, one per
zone:

```hcl
resource "google_compute_instance_group" "worker" {
  name      = "ig-members-worker"
  zone      = google_compute_instance.worker.zone
  instances = [google_compute_instance.worker.self_link]

  named_port {
    name = "http"
    port = 8080
  }
}

module "gateway_backend_worker" {
  source = "github.com/bcc-code/bcc-platform-gateway-tf-modules//gateway-backend-vm?ref=main"

  app         = "members"
  component   = "worker"
  environment = local.props.app_environment

  instance_groups = [google_compute_instance_group.worker.self_link]
  # or: [google_compute_region_instance_group_manager.worker.instance_group]

  port = 8080
  health_check = {
    request_path = "/healthz"
  }

  firewall = {
    network     = google_compute_network.main.self_link
    target_tags = ["gateway-backend"]
  }
}
```

- **Named ports.** The backend service sends traffic to the named port
  `port_name` (default `http`), so every group must declare it. `port` is the
  number it maps to, and is used only for the firewall rule.
- **Open the firewall.** The gateway health-checks and proxies from Google's
  front ends, `35.191.0.0/16` and `130.211.0.0/22`; without a rule admitting
  them, every backend stays unhealthy and the gateway returns 502s. `firewall`
  creates that rule — leave it null only if one already exists. With a Shared
  VPC, set `firewall.project` to the host project.
- **The health check must get a 200.** A redirect to HTTPS or a login page
  counts as unhealthy, so point `request_path` at an endpoint that answers
  plainly.
- **One load-balanced group per VM.** A VM can't be in two.
- The VMs need no external IP: the gateway reaches them over Google's network.

## Custom headers

All modules take `custom_response_headers`, added by the load balancer to every
response from the backend, and `gateway-backend` and `gateway-backend-vm` also
take `custom_request_headers`, added to every request they forward. Each
entry is `"Name: value"`, and values may use the load balancer's header
variables:

```hcl
module "gateway_backend" {
  # ...
  custom_request_headers = [
    "X-Client-Region: {client_region}",
  ]
  custom_response_headers = [
    "Strict-Transport-Security: max-age=31536000",
    "X-Frame-Options: DENY",
  ]
}
```

- **No request headers for a bucket.** A backend bucket, unlike a backend
  service, cannot add headers to the request it sends to Cloud Storage.
- **Do not rewrite `Host`.** Cloud Run needs the original host to match its
  custom domain.

## What you don't pass

- **The gateway's service accounts.** One gateway per tier, so the two service
  account emails are constants inside the modules, and `environment` selects the
  tier: `prod`/`staging` → prod gateway, `dev`/`sandbox` → sandbox gateway. A
  sandbox pipeline therefore cannot grant access to a prod-tier gateway.
- **Anything else about the gateway** — project, URL map. Nothing here reads the
  gateway's state, and the gateway reads nothing of yours.

## Two backends in one project

The `roles/compute.loadBalancerServiceUser` grant is project-scoped, so one is
enough for every backend in the project. Leave it on one instance and turn it off
on the rest; two instances managing the identical binding apply cleanly and then
remove it from under each other on the first destroy.

```hcl
module "gateway_backend_api" {
  # ...                       grant_gateway_access defaults to true
}

module "gateway_backend_ui" {
  # ...
  grant_gateway_access = false
}
```

## Then: the route

The gateway builds its reference from the naming convention alone — there is no
output to wire up and no state dependency between the repos:

| Module                 | Creates                      | Referenced as                                    |
| ---------------------- | ---------------------------- | ------------------------------------------------ |
| gateway-backend        | `bs-<app>-<component>-<env>` | `projects/<project>/global/backendServices/bs-…` |
| gateway-backend-bucket | `bb-<app>-<component>-<env>` | `projects/<project>/global/backendBuckets/bb-…`  |
| gateway-backend-vm     | `bs-<app>-<component>-<env>` | `projects/<project>/global/backendServices/bs-…` |

So `app`, `component` and the environment must match the `app` field, backend key
and environment in `routes/<app>.yaml` in
[bcc-code/bcc-platform-gateway](https://github.com/bcc-code/bcc-platform-gateway).
The `route_registry_snippet` output prints the fragment to add there:

```yaml
app: members

environments:
  prod:
    project_id: bcc-members-prod

backends:
  api:
    type: cloud_run
  ui:
    type: backend_bucket
  worker:
    type: vm
```

**Apply your repo before that gateway PR merges.** A URL map cannot reference a
backend that does not exist, and the gateway's plan fails on it. Renaming or
destroying a published backend is likewise coordinated: remove the route from the
gateway first, then the module here. In the gateway repo, see
[routes/README.md](https://github.com/bcc-code/bcc-platform-gateway/blob/main/routes/README.md)
for the registry schema and
[MIGRATION.md](https://github.com/bcc-code/bcc-platform-gateway/blob/main/MIGRATION.md)
for how applications are being onboarded.
