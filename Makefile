IMAGE ?= docker.io/instantprachi/summerint-site
TAG   ?= latest
JENKINS_URL ?= http://localhost:8080

.PHONY: help build push dev dev-down prod prod-down tf-init tf-plan tf-apply tf-destroy deps play play-check lint deploy deploy-dry jenkins jenkins-down jenkins-pass webhook-test

help:
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build the site image
	docker build -t $(IMAGE):$(TAG) app/

push: build ## Build and push the image
	docker push $(IMAGE):$(TAG)

dev: ## Run the dev stack (localhost:8080)
	cd compose && docker compose up -d --build

dev-down:
	cd compose && docker compose down

prod: ## Run the prod stack + watchtower
	cd compose && docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

prod-down:
	cd compose && docker compose -f docker-compose.yml -f docker-compose.prod.yml down

tf-init: ## terraform init
	cd terraform && terraform init

tf-plan:
	cd terraform && terraform plan

tf-apply: ## Create the EC2 infrastructure
	cd terraform && terraform apply

tf-destroy: ## Tear everything down
	cd terraform && terraform destroy

deps: ## Install the Ansible collections
	cd ansible && ansible-galaxy collection install -r requirements.yml

play: ## Run the playbook
	cd ansible && ansible-playbook site.yml

play-check: ## Dry run
	cd ansible && ansible-playbook site.yml --check --diff

deploy: ## Task 4: SSH deploy to the EC2 instance
	./scripts/deploy-ec2.sh

deploy-dry: ## Task 4: print the remote script, connect to nothing
	./scripts/deploy-ec2.sh --dry-run

jenkins: ## Task 5: start the Jenkins controller
	docker compose -f jenkins/docker-compose.yml up -d --build

jenkins-down:
	docker compose -f jenkins/docker-compose.yml down

jenkins-pass: ## Print the Jenkins initial admin password
	docker exec summerint-jenkins cat /var/jenkins_home/secrets/initialAdminPassword

webhook-test: ## Task 6: probe the Jenkins webhook endpoint
	./scripts/test-webhook.sh --url $(JENKINS_URL)

lint: ## Validate everything that can be validated locally
	cd terraform && terraform fmt -check && terraform validate
	cd ansible && ansible-lint site.yml || true
	cd compose && docker compose config -q && \
	  docker compose -f docker-compose.yml -f docker-compose.prod.yml config -q
	docker compose -f jenkins/docker-compose.yml config -q
	bash -n scripts/deploy-ec2.sh scripts/test-webhook.sh
