# Convenience wrapper. While learning, prefer running the terraform commands by
# hand (see README) so you read every plan before applying it.

TF          := terraform
STAGES      := stages
KUBECONFIG  := $(CURDIR)/$(STAGES)/01-cluster/kubeconfig
CLUSTER     := lab
# Image tag = hash of the app source, so a code change -> new tag -> rolling update.
TAG         := $(shell cat app/* | shasum | cut -c1-10)
IMAGE       := notes-api:$(TAG)
URL         := http://notes.localhost:8088

export KUBECONFIG

.PHONY: up down cluster platform aws image app test status fmt validate

up: cluster platform aws app test ## Build everything, in order

cluster:
	$(TF) -chdir=$(STAGES)/01-cluster init -input=false
	$(TF) -chdir=$(STAGES)/01-cluster apply -auto-approve

platform:
	$(TF) -chdir=$(STAGES)/02-platform init -input=false
	$(TF) -chdir=$(STAGES)/02-platform apply -auto-approve

aws:
	$(TF) -chdir=$(STAGES)/03-aws init -input=false
	$(TF) -chdir=$(STAGES)/03-aws apply -auto-approve

image: ## Build the app image and copy it into the kind nodes (no registry needed)
	docker build -t $(IMAGE) app
	kind load docker-image $(IMAGE) --name $(CLUSTER)

app: image
	$(TF) -chdir=$(STAGES)/04-app init -input=false
	$(TF) -chdir=$(STAGES)/04-app apply -auto-approve -var image=$(IMAGE)
	kubectl -n notes rollout status deploy/notes-api --timeout=120s

test: ## Smoke test through the ingress (retries: Traefik needs a moment to see new pods)
	curl -fsS --retry 15 --retry-all-errors --retry-delay 1 $(URL)/ && echo
	curl -fsS -X POST $(URL)/notes -H 'content-type: application/json' -d '{"text":"hello from make test"}' && echo
	curl -fsS $(URL)/notes && echo

status:
	kubectl get nodes
	kubectl get pods -A

down: ## Destroy in reverse order (each stage depends on the previous one)
	-$(TF) -chdir=$(STAGES)/04-app destroy -auto-approve -var image=$(IMAGE)
	-$(TF) -chdir=$(STAGES)/03-aws destroy -auto-approve
	-$(TF) -chdir=$(STAGES)/02-platform destroy -auto-approve
	$(TF) -chdir=$(STAGES)/01-cluster destroy -auto-approve

fmt:
	$(TF) fmt -recursive

validate: fmt
	@for s in $(STAGES)/*/; do echo "== $$s"; $(TF) -chdir=$$s init -backend=false -input=false >/dev/null && $(TF) -chdir=$$s validate; done
