# SummerInt — Cloud + DevOps Project

An nginx static site, containerized with Docker, provisioned on AWS with
Terraform, and configured with Ansible — with Watchtower keeping the running
container up to date automatically.

```
app/          the site + Dockerfile (the image everything else deploys)
terraform/    Task 2 — EC2 + VPC + security group (ports 80, 22) + Docker via user_data
ansible/      Task 1 — install Docker, pull the image, run the container
compose/      Task 3 — multi-environment compose stack (nginx + watchtower)
scripts/      Task 4 — SSH deploy to EC2;  Task 6 — webhook verification
Jenkinsfile   Task 5 — declarative build/push pipeline  (+ Task 6 trigger)
jenkins/      a ready-to-run Jenkins controller for Tasks 5 & 6
docs/         per-task notes
```

## Order of operations

```
terraform apply        ->  server exists, Docker installed, inventory written
ansible-playbook       ->  image pulled, stack running, health-checked
scripts/deploy-ec2.sh  ->  (alternative to Ansible) SSH + pull + run
git push origin main   ->  webhook -> Jenkins -> build -> push to Docker Hub
                                                     └-> Watchtower redeploys
```

Tasks 1–3 stand alone; Tasks 4–6 add a manual deploy path and a CI pipeline on
top of the same image. Nothing in 4–6 changes how 1–3 behave.

---

## 0. Build and push the image

Everything downstream deploys `IMAGE_NAME:IMAGE_TAG`, so publish it once.

```bash
export IMAGE=docker.io/instantprachi/summerint-site
docker build -t $IMAGE:latest app/
docker login
docker push $IMAGE:latest
```

Then set that name in two places:
- `ansible/group_vars/all.yml` → `app_image_name`
- `compose/.env` → `IMAGE_NAME`

---

## Task 2 — Terraform: EC2 infrastructure

Creates a dedicated VPC, public subnet, internet gateway and route table, a
security group opening **80** and **22**, an EC2 instance (Amazon Linux 2023),
and an Elastic IP. `user_data.sh` installs Docker and the Compose plugin at
first boot.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then edit
terraform init
terraform plan
terraform apply
```

Outputs give you `site_url`, `ssh_command`, and `public_ip`. Terraform also
writes `ansible/inventory/hosts.ini` for you, so Task 1 needs no manual setup.

**Before applying:** narrow SSH to your own address —

```bash
curl -s ifconfig.me
```

and put `<that-ip>/32` in `ssh_allowed_cidr`. It defaults to `0.0.0.0/0` only so
the lab works out of the box.

Teardown:

```bash
cd terraform && terraform destroy
```

---

## Task 1 — Ansible: configuration management

Installs Docker, pulls the image, and runs the container so it survives reboots
(`restart_policy: unless-stopped` plus `systemctl enable docker`).

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml
```

Useful variations:

```bash
ansible-playbook site.yml --check --diff        # dry run
ansible-playbook site.yml -e app_image_tag=v2   # deploy a specific tag
ansible-playbook site.yml --tags app            # redeploy only, skip Docker install
ansible-playbook site.yml -e app_deploy_mode=container   # single container, no compose
```

The playbook is idempotent — a second run reports no changes. It ends by
polling `/healthz` until the site answers, so a green run means the site is
genuinely serving.

Private registry? Put `registry_username` / `registry_password` in an
Ansible Vault file rather than `group_vars/all.yml`:

```bash
ansible-vault create group_vars/vault.yml
ansible-playbook site.yml --ask-vault-pass
```

---

## Task 3 — Docker Compose, multi-environment

Three files, layered:

| file | role |
|---|---|
| `docker-compose.yml` | base — the nginx service |
| `docker-compose.override.yml` | **dev** — builds locally, bind-mounts the site, no Watchtower |
| `docker-compose.prod.yml` | **prod** — pulls the published image, adds Watchtower, log rotation, memory limit |

```bash
cd compose
cp .env.example .env

# development (auto-loads the override; .env sets HTTP_PORT=8080)
docker compose up -d --build
curl localhost:8080/healthz    # 8080 only if .env sets HTTP_PORT; otherwise 80

# production
HTTP_PORT=80 docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Verify which config you're really getting before running it:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml config
```

### Watchtower

Runs with `--label-enable`, so it only updates containers carrying
`com.centurylinklabs.watchtower.enable=true` — the `web` service does, nothing
else on the host will be touched. It polls every `WATCHTOWER_POLL_INTERVAL`
seconds (default 300), pulls a newer digest for the same tag, restarts the
container, and `--cleanup` removes the old image.

Push a new `:latest` and it deploys itself within the poll interval:

```bash
docker build -t $IMAGE:latest app/ && docker push $IMAGE:latest
docker logs -f summerint-watchtower
```

> Watchtower tracks the **digest behind a tag**. Pinning `IMAGE_TAG` to an
> immutable version like `v1.2.0` means nothing will ever auto-update — use a
> moving tag (`latest`, `stable`) for the auto-update behavior.

---

## Task 4 — Deploy to EC2 over SSH

`scripts/deploy-ec2.sh` SSHes in, pulls from Docker Hub, and runs the container.
It's the manual counterpart to Task 1 — no Ansible needed.

```bash
./scripts/deploy-ec2.sh                       # host from terraform output
./scripts/deploy-ec2.sh --host 203.0.113.10 --port 8080
./scripts/deploy-ec2.sh --host 203.0.113.10 --dry-run   # print, don't connect
```

Re-running replaces the container in place, so this is also the redeploy
command. Port 8080 needs `extra_ingress_ports = [8080]` in `terraform.tfvars`
(or an SSH tunnel). Full detail: [docs/task-04-deploy-ec2.md](docs/task-04-deploy-ec2.md).

---

## Task 5 — Jenkins pipeline

`Jenkinsfile` (declarative): checkout → lint → build image → smoke-test the
image → push to `instantprachi/summerint-site` as `<branch>-<sha>`, `latest`,
and `build-<n>`. Publishing is gated on `main`.

Bring up a controller that already has the plugins and the Docker CLI:

```bash
cp jenkins/.env.example jenkins/.env      # set JENKINS_URL
docker compose -f jenkins/docker-compose.yml up -d --build
docker exec summerint-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Then add a **Username with password** credential with ID **`dockerhub-creds`**
(password = a Docker Hub *access token*) and create a Multibranch Pipeline
pointing at this repo. Full detail: [docs/task-05-jenkins-pipeline.md](docs/task-05-jenkins-pipeline.md).

---

## Task 6 — GitHub webhook

The pipeline declares `triggers { githubPush() }`. On GitHub, add a webhook:

```
Payload URL:   http://<jenkins-host>:8080/github-webhook/
Content type:  application/json
Events:        just the push event
```

Jenkins must be reachable from GitHub — set `jenkins_ingress_enabled = true` in
`terraform.tfvars` to open 8080, or tunnel with ngrok.

```bash
./scripts/test-webhook.sh --url http://<jenkins-host>:8080             # probe
./scripts/test-webhook.sh --url http://<jenkins-host>:8080 --simulate  # fake push
```

> A declarative `triggers` block only registers **after the job has run once**.
> Build manually one time before testing the webhook — this is the usual reason
> a 200 delivery produces no build.

Full detail, including how to restrict to `main`: [docs/task-06-webhook.md](docs/task-06-webhook.md).

---

## Verifying the whole chain

```bash
cd terraform && terraform output site_url     # -> http://<eip>
curl -f $(terraform output -raw site_url)/healthz    # -> ok
```

On the server:

```bash
ssh -i ~/.ssh/id_rsa ec2-user@<eip>
docker ps                       # summerint-web + summerint-watchtower, healthy
docker compose -f /opt/summerint/docker-compose.yml ps
sudo cat /var/log/bootstrap-docker.log       # what user_data installed
```

## Notes on choices

- **Dedicated VPC** instead of the default VPC — some accounts don't have one,
  and this keeps the lab self-contained and destroyable in one command.
- **Docker installed twice** (Terraform `user_data` *and* Ansible) on purpose:
  `user_data` makes the box usable immediately, Ansible makes it reproducible
  and works on servers Terraform didn't create. Both are idempotent.
- **IMDSv2 required** and the root volume is encrypted.
- **Compose over `docker run`** on the server so Task 3's stack is the single
  source of truth for what runs; `app_deploy_mode=container` is kept as an
  alternative for the plain single-container case.
