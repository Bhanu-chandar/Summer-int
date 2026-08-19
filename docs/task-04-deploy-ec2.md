# Task 4 — Deploy to EC2

> SSH into an AWS EC2 instance. Pull Docker image from Docker Hub. Run the
> container and expose it on port 80 or 8080.

[`scripts/deploy-ec2.sh`](../scripts/deploy-ec2.sh) does all three over a single
SSH session. It is the manual/imperative counterpart to the Ansible playbook —
same end state, no Ansible required.

## Usage

```bash
# host taken from `terraform output -raw public_ip`
./scripts/deploy-ec2.sh

# explicit everything
./scripts/deploy-ec2.sh \
  --host 203.0.113.10 \
  --user ec2-user \
  --key ~/.ssh/id_rsa \
  --image docker.io/instantprachi/summerint-site \
  --tag latest \
  --port 80

# see exactly what would run on the server, without connecting
./scripts/deploy-ec2.sh --host 203.0.113.10 --dry-run
```

Private image? Export credentials and the script logs in on the remote host:

```bash
export DOCKERHUB_USER=instantprachi
export DOCKERHUB_TOKEN=<access-token>
./scripts/deploy-ec2.sh
```

## What runs on the instance

1. Verifies Docker exists and the daemon is up (starts it if not).
2. `docker login` — only when credentials were supplied.
3. `docker pull <image>:<tag>`.
4. `docker rm -f` the old container, then `docker run -d --restart unless-stopped -p <port>:80`.
5. Polls `/healthz` for up to 60s; dumps container logs and fails if it never becomes healthy.
6. `docker image prune -f` to reclaim the old layers.

Re-running is safe — step 4 replaces the container in place, so this doubles as
the redeploy command.

## Port 80 vs 8080

The security group opens **80** and **22** by default. Deploying on 8080 needs
one of:

```hcl
# terraform/terraform.tfvars
extra_ingress_ports = [8080]
```

```bash
terraform apply
./scripts/deploy-ec2.sh --port 8080
```

…or no infrastructure change at all, via an SSH tunnel:

```bash
ssh -i ~/.ssh/id_rsa -L 8080:localhost:8080 ec2-user@<ip>
curl http://localhost:8080/healthz
```

## Relationship to Task 1

Both put the same container on the box. Use whichever fits:

| | `deploy-ec2.sh` | `ansible-playbook site.yml` |
|---|---|---|
| installs Docker | no (expects it) | yes |
| runs the container | yes | yes |
| multiple hosts | one at a time | all of `[web]` at once |
| Watchtower stack | no (single container) | yes (compose) |
| needs Ansible installed | no | yes |

They don't conflict, but they do manage a container of the same name — running
one after the other simply replaces it.
