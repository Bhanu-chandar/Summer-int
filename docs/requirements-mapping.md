# Requirement → implementation map

Where each line of the three task briefs is satisfied.

## Task 1 — Ansible for Configuration Management

> Write an Ansible playbook to: Install Docker. Pull your image. Run container
> automatically on server.

| Requirement | Where | Detail |
|---|---|---|
| Ansible playbook | `ansible/site.yml` | two roles, tagged `docker` / `app` |
| Install Docker | `ansible/roles/docker/tasks/main.yml` | dnf (AL2023/RHEL) or the official apt repo (Ubuntu); enables the service; adds the login user to the `docker` group; installs the Compose v2 plugin if missing |
| Pull your image | `ansible/roles/app/tasks/main.yml` | `community.docker.docker_image` with `force_source: true` + retries; optional `docker_login` for private registries |
| Run container automatically | same file | `docker_compose_v2` (default) or `docker_container`, both with `restart_policy: unless-stopped`, plus `systemctl enable docker` so it returns after a reboot |
| — verification | same file | polls `/healthz` up to 12 times; the play fails if the site never answers |

Idempotent: a second run reports `changed=0`.

## Task 2 — Terraform to Create EC2 Infrastructure

> Launch EC2 instance. Open port 80 and 22. Install Docker using user_data or SSH.

| Requirement | Where | Detail |
|---|---|---|
| Launch EC2 instance | `terraform/main.tf` → `aws_instance.web` | Amazon Linux 2023 AMI resolved via data source, gp3 encrypted root, IMDSv2 required, Elastic IP attached |
| Open port 80 | `aws_vpc_security_group_ingress_rule.http` | `var.http_allowed_cidr`, default `0.0.0.0/0` |
| Open port 22 | `aws_vpc_security_group_ingress_rule.ssh` | `var.ssh_allowed_cidr` — narrow this to your IP |
| Install Docker via user_data | `terraform/user_data.sh` | installs Docker + Compose plugin, enables the service, writes `/var/log/bootstrap-docker.log` |
| supporting network | `main.tf` | VPC, public subnet, IGW, route table + association |
| hand-off | `local_file.ansible_inventory` | writes `ansible/inventory/hosts.ini` so Task 1 runs with zero manual config |

## Task 3 — Docker Compose for Multi-Environment

> Create a docker-compose.yml to run: nginx for static site. Add optional
> container like watchtower for auto-updates.

| Requirement | Where | Detail |
|---|---|---|
| nginx for static site | `compose/docker-compose.yml` → `web` | serves the image built from `app/`, healthcheck on `/healthz` |
| multi-environment | `docker-compose.override.yml` (dev) + `docker-compose.prod.yml` (prod) | dev builds locally and bind-mounts the site on 8080; prod pulls the published image on 80 with log rotation and a memory limit |
| watchtower for auto-updates | `docker-compose.prod.yml` → `watchtower` | `--label-enable --cleanup --rolling-restart`; only updates containers labelled `com.centurylinklabs.watchtower.enable=true` |
| optional | — | Watchtower lives only in the prod overlay, and in the Ansible-rendered stack it is gated behind `watchtower_enabled` |

## Cross-task wiring

```
app/Dockerfile ──build/push──> registry
       │                          │
terraform apply                   │  pulled by
   ├─ EC2 + SG(80,22) + Docker    │
   └─ writes ansible inventory ───┤
                                  ▼
              ansible-playbook site.yml
                 └─ renders the Task 3 compose stack to /opt/summerint
                        └─ watchtower watches the registry for new digests
```

---

## Task 4 — Deploy to EC2 Instance

> SSH into an AWS EC2 instance. Pull Docker image from Docker Hub. Run the
> container and expose it on port 80 or 8080.

| Requirement | Where | Detail |
|---|---|---|
| SSH into EC2 | `scripts/deploy-ec2.sh` | resolves the host from `terraform output -raw public_ip` when `--host` is omitted; `bash -s` streams the remote script over one SSH session |
| Pull image from Docker Hub | same, remote section | `docker pull`, with optional `docker login` when `DOCKERHUB_USER`/`DOCKERHUB_TOKEN` are exported |
| Run the container | same | `docker run -d --restart unless-stopped`, replacing any previous container of the same name |
| Expose on 80 or 8080 | `--port` flag | 80 by default; 8080 supported via `extra_ingress_ports = [8080]` (new Terraform variable) or an SSH tunnel |
| — verification | same | polls `/healthz` for 60s and dumps logs on failure |
| — safety | same | `--dry-run` prints the remote script without connecting |

## Task 5 — Configure Jenkins Pipeline

> Create a Jenkinsfile (Declarative) that: Pulls code from GitHub. Builds Docker
> image. Pushes image to Docker Hub (use instantprachi namespace).

| Requirement | Where | Detail |
|---|---|---|
| Declarative Jenkinsfile | `Jenkinsfile` | `pipeline { }` with `options`, `triggers`, `environment`, `stages`, `post` |
| Pulls code from GitHub | `stage('Checkout')` | `checkout scm` — builds the triggering commit; derives `GIT_SHA` |
| Builds Docker image | `stage('Build image')` | `docker.build` on `app/`, labelled with the git revision |
| Pushes to Docker Hub | `stage('Push to Docker Hub')` | `docker.withRegistry(..., 'dockerhub-creds')` |
| `instantprachi` namespace | `environment { DOCKERHUB_NS = 'instantprachi' }` | image = `docker.io/instantprachi/summerint-site` |
| — extras | `stage('Smoke test image')`, `post` | runs the built image and health-checks it before publishing; cleans images and workspace afterwards |
| — supporting setup | `jenkins/` | controller image with the Docker CLI + required plugins pre-installed |

## Task 6 — Add Webhook Integration

> Connect GitHub with Jenkins via webhook. On code push to main, trigger the
> Jenkins job automatically.

| Requirement | Where | Detail |
|---|---|---|
| Jenkins accepts the webhook | `Jenkinsfile` → `triggers { githubPush() }` | plus the `github` plugin in `jenkins/plugins.txt` |
| GitHub → Jenkins connection | `docs/task-06-webhook.md` | exact payload URL, content type, event selection, secret handling |
| Reachability | `terraform/` → `jenkins_ingress_enabled` | opens 8080 to `jenkins_allowed_cidr`; a precondition prevents clashing with `extra_ingress_ports = [8080]` |
| Triggers on push to main | `docs/task-06-webhook.md` §5 | Multibranch (per-branch jobs) or Branch Specifier `*/main`; the push stage is additionally gated by `when { branch 'main' }` |
| — verification | `scripts/test-webhook.sh` | probes `/github-webhook/`, and `--simulate` POSTs a real-shaped GitHub push payload |
