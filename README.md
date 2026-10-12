# k8s-terraform-lab

Learn Terraform + Kubernetes by building a realistic stack **entirely on your Mac** —
no AWS account, no bill. Terraform creates a Kubernetes cluster (kind), installs
platform services with Helm, creates "AWS" resources in LocalStack, and deploys an
app that uses them.

```
                         your Mac
  ┌──────────────────────────────────────────────────────────────────┐
  │  terraform ──► kind cluster "lab" (Docker containers)            │
  │                ┌───────────────────────────────────────────────┐ │
  │  :8088 ───────►│ traefik (ingress) ──► Service ──► notes-api ×2│ │
  │                │                                    │ (pods)   │ │
  │  :4566 ───────►│ localstack (fake AWS: S3, IAM) ◄───┘          │ │
  │                └───────────────────────────────────────────────┘ │
  └──────────────────────────────────────────────────────────────────┘
```

| Stage | Terraform provider | Creates | On real AWS this would be |
|---|---|---|---|
| `stages/01-cluster`  | `tehcyx/kind`          | 2-node Kubernetes cluster | VPC + EKS |
| `stages/02-platform` | `hashicorp/helm`       | Traefik ingress, LocalStack | AWS Load Balancer Controller |
| `stages/03-aws`      | `hashicorp/aws`        | S3 bucket + IAM user (via a module) | the same code, minus the `endpoints` block |
| `stages/04-app`      | `hashicorp/kubernetes` | Namespace, ConfigMap, Secret, Deployment, Service, Ingress | identical |

Each stage is its own Terraform **root module** with its own **state**, and reads
earlier stages' outputs with `terraform_remote_state`. That's how real teams split
infrastructure: by lifecycle and blast radius.

## Prerequisites

Docker Desktop (give it ≥ 6 GB RAM), `terraform`, `kind`, `kubectl`, `helm`. Optional: `aws` CLI.

---

## The walkthrough (do it by hand the first time)

Run everything from the repo root. Set this once per terminal so `kubectl` talks to the lab cluster:

```bash
export KUBECONFIG=$PWD/stages/01-cluster/kubeconfig
```

### Stage 01 — the cluster

```bash
cd stages/01-cluster
terraform init      # downloads the kind provider, writes .terraform.lock.hcl
terraform plan      # read it! "+ create" = new resource
terraform apply
terraform output    # the values later stages will consume
cd ../..
kubectl get nodes   # lab-control-plane, lab-worker
docker ps           # ...which are just Docker containers
```

**Notice:**
- `terraform.tfstate` appeared. Open it — it's JSON describing what Terraform thinks exists. Terraform compares *code* ↔ *state* ↔ *reality* on every plan.
- Run `terraform plan` again: "No changes". Terraform is **declarative and idempotent**.
- Change `ingress_host_port` in `variables.tf` and plan: `-/+ must be replaced`. Some attributes can't be changed in place, so Terraform destroys and recreates. *Always read the plan for replacements.* (Change it back.)

### Stage 02 — platform services via Helm

```bash
cd stages/02-platform && terraform init && terraform apply && cd ../..
kubectl get pods -n traefik
kubectl get pods -n localstack
curl -s localhost:4566/_localstack/health | head -c 300
```

**Notice:**
- `data "terraform_remote_state" "cluster"` reads stage 01's outputs. Try `terraform console` and type `local.cluster` to see them.
- `values = [yamlencode({...})]` — Terraform's HCL objects turned into Helm values.
- `helm list -A` shows the releases Terraform created. Terraform drives Helm; Helm drives Kubernetes.

### Stage 03 — "AWS" resources

```bash
cd stages/03-aws && terraform init && terraform apply
terraform output                         # secret is shown as (sensitive)
terraform output -raw app_secret_access_key   # ...but it's readable, and it's in the state file
terraform state list                     # every resource Terraform tracks, incl. ones inside the module
terraform state show module.notes_bucket.aws_s3_bucket.this
cd ../..
```

If you have the aws CLI:

```bash
aws --endpoint-url http://localhost:4566 s3 ls
```

**Notice:**
- `module "notes_bucket"` calls `modules/notes-bucket`. Modules are functions: inputs (`variables.tf`), body (`main.tf`), return values (`outputs.tf`).
- `default_tags` in the provider are applied to every resource automatically.
- `validation` blocks reject bad input at plan time (`terraform plan -var environment=qa`).
- `data "aws_iam_policy_document"` builds JSON policy safely instead of hand-written strings.

### Stage 04 — the app

```bash
make image                          # docker build + `kind load` into the cluster
cd stages/04-app && terraform init
terraform apply -var image=notes-api:$(cat ../../app/* | shasum | cut -c1-10)
cd ../..

kubectl -n notes get deploy,rs,pods,svc,ingress
curl http://notes.localhost:8088/
curl -X POST http://notes.localhost:8088/notes -H 'content-type: application/json' -d '{"text":"my first note"}'
curl http://notes.localhost:8088/notes
```

Hit `/` several times — the `pod` field changes: the Service load-balances across both replicas.

**Notice (Kubernetes):**
- **Deployment → ReplicaSet → Pods.** You declare "2 replicas of this template"; controllers make it so.
- **Probes:** `/healthz` (liveness → restart if failing) vs `/readyz` (readiness → remove from Service if failing). The readiness check calls S3 — that's the right place for dependency checks.
- **ConfigMap vs Secret**, injected as env vars with `env_from`.
- **Service** gives pods a stable DNS name: `notes-api.notes.svc.cluster.local`. **Ingress** routes by `Host:` header from outside.
- The `checksum/config` annotation: env vars are only read at pod start, so a config change must roll the pods. Change `replicas` or a ConfigMap value and `terraform apply` to watch it (`kubectl -n notes get pods -w`).

### Shortcut / teardown

```bash
make up      # all four stages + smoke test
make down    # destroy in reverse order
```

---

## Terraform concepts — where to find each one

| Concept | Where |
|---|---|
| `terraform` block, `required_providers`, version constraints (`~>`) | top of every `stages/*/main.tf` |
| Lock file (exact provider builds — commit it) | `.terraform.lock.hcl` after `init` |
| Providers & provider configuration | `provider "kind"`, `"helm"`, `"aws"`, `"kubernetes"` |
| Resources & implicit dependencies (`a.b.attr` references) | everywhere; e.g. bucket → versioning |
| Variables, types, defaults, `validation` | `variables.tf` files |
| Outputs, `sensitive` | `outputs.tf` files |
| Locals | `locals {}` in stages 02–04 |
| Data sources | `terraform_remote_state`, `aws_iam_policy_document` |
| Modules (local) | `modules/notes-bucket`, called from `stages/03-aws` |
| Built-in functions | `abspath`, `yamlencode`, `jsonencode`, `sha256`, `trimprefix`, `can`, `regex`, `contains` |
| State & splitting state by layer | one `terraform.tfstate` per stage |
| Replacement vs in-place update | Stage 01 exercise |

Commands to get comfortable with: `init`, `fmt`, `validate`, `plan`, `apply`, `destroy`, `output`, `console`, `state list/show/rm/mv`, `import`, `apply -replace=ADDR`, `plan -refresh-only`, `graph`.

---

## Exercises (roughly easiest → hardest)

1. **Scale:** set `replicas = 3` in `stages/04-app` and apply. Then `kubectl scale deploy/notes-api -n notes --replicas=1` and run `terraform plan` — Terraform detects the **drift** and wants to put it back.
2. **Ship a code change:** edit `app/app.py` (e.g. add a field to `/`), then `make app`. Watch a zero-downtime rolling update with `kubectl -n notes get pods -w`.
3. **Break readiness:** temporarily set `NOTES_BUCKET` to a bucket that doesn't exist. Pods go `0/1 Ready`, and because `max_unavailable = 0`, the old pods keep serving. Revert.
4. **`count` / `for_each`:** in `stages/03-aws`, create one bucket per environment with `for_each = toset(["dev", "staging"])` over the module. Look at the resource addresses in `terraform state list`.
5. **`moved` block:** rename `module.notes_bucket` to `module.notes`. Plan shows destroy/create — add a `moved { from = ... to = ... }` block so it becomes a no-op rename.
6. **Import:** create a bucket with the aws CLI, then bring it under Terraform with an `import {}` block.
7. **Remote state backend:** move stage 03's state into an S3 bucket in LocalStack (`backend "s3"` with `endpoints`, `use_path_style = true`, `skip_*` flags), then `terraform init -migrate-state`. Think about the chicken-and-egg: where does the *state bucket's* state live?
8. **Your own module:** extract the Deployment+Service+Ingress in stage 04 into `modules/k8s-web-app` and use it to deploy a second app.
9. **Workspaces vs directories:** try `terraform workspace new staging` in stage 03 with `environment = terraform.workspace`. Compare with the "one directory per env" approach.
10. **Go to real AWS** (when ready, costs money): replace stage 01 with the `terraform-aws-modules/eks` module, delete the `endpoints`/`skip_*`/fake keys in stage 03, and swap the IAM access key for EKS Pod Identity.

---

## Two real failures hit while building this lab (worth understanding)

1. **Helm `wait` timed out on Traefik.** The chart's Service defaults to `type: LoadBalancer`. On AWS, a controller provisions a load balancer and fills in an address; kind has no such controller, so the address stays `<pending>` forever and `wait = true` never finishes. Fix: `service.spec.type = NodePort` (plus the kind port mapping from stage 01). Lesson: `kubectl get svc` / `kubectl describe` before blaming Terraform.
2. **"cannot re-use a name that is still in use".** The failed install was left in the cluster, but Terraform didn't record it in state. Terraform then tried to *create* something that already existed. Terraform only manages what's in its state. Two ways out: delete the orphan (`helm uninstall traefik -n traefik`), or adopt it (`terraform import`). Prevention: `atomic = true` on `helm_release` rolls back failed installs.

## Troubleshooting

- **Port already in use** — change `ingress_host_port` / `localstack_host_port` in `stages/01-cluster/variables.tf` (requires recreating the cluster), and update `URL` in the `Makefile`.
- **LocalStack "License activation failed"** — newer LocalStack images need an account token. This lab pins `4.14`, the last community release that runs without one.
- **`ImagePullBackOff` on notes-api** — the image wasn't loaded into kind, or the tag differs. Run `make image` and pass the same tag to `-var image=`.
- **Stuck namespace / leftover state after deleting the cluster manually** — `kind delete cluster --name lab`, then delete the `terraform.tfstate*` files in stages 02–04 (their resources lived inside the cluster).
