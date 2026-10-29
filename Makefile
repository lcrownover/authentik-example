.PHONY: run seed stop plan terraform uo clean help

run: ## Start authentik and apply terraform (safe to re-run)
	./run.sh

seed: ## Create the devuser dev user (with an SSH key) in authentik Admins
	./seed-dev-user.sh

stop: ## Stop containers, keeping data
	docker compose down

plan: ## Show pending changes to the environment
	terraform plan -var-file=env.tfvars

terraform: ## Apply the environment config only
	terraform apply -var-file=env.tfvars

uo: ## Apply the uo stack (groups and members)
	terraform -chdir=stacks/uo init -input=false
	terraform -chdir=stacks/uo apply -var-file=env.tfvars -auto-approve

clean: ## Delete containers, the database and all terraform state
	docker compose down -v
	rm -f terraform.tfstate* stacks/uo/terraform.tfstate* ldap.env

help: ## List targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-10s %s\n", $$1, $$2}'
