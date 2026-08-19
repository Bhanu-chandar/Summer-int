# Troubleshooting

**`terraform apply` fails on `aws_key_pair`: no such file**
`var.public_key_path` points at a key you don't have. Generate one:
`ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa`

**Ansible: "Failed to connect to the host via ssh"**
The instance is still booting. The playbook's `wait_for_connection` covers up to
5 minutes; beyond that check that your current IP matches `ssh_allowed_cidr`.

**Ansible: "permission denied while trying to connect to the Docker daemon"**
The `docker` group membership only applies to new sessions. Every Docker task in
this repo runs with `become: true`, so this shouldn't surface — if it does after
a manual `docker ps`, reconnect your SSH session.

**Site returns nothing on port 80**
```bash
docker ps -a                    # is summerint-web running or restarting?
docker logs summerint-web
curl -f localhost/healthz       # from on the server — isolates SG vs container
```
If it works locally but not from outside, it's the security group.

**Watchtower never updates anything**
- The tag is immutable (`v1.2.0`) — nothing new to find. Use a moving tag.
- The container is missing the `com.centurylinklabs.watchtower.enable=true`
  label; with `--label-enable` Watchtower ignores unlabelled containers.
- Private registry: mount credentials into the Watchtower container (the
  commented-out `~/.docker/config.json` volume in `docker-compose.prod.yml`).
- Check `docker logs summerint-watchtower` — it logs each poll.

**Compose publishes two ports in dev**
Don't re-declare `ports` in an override file; Compose *appends* list entries
across files. Change `HTTP_PORT` in `compose/.env` instead.

**`docker compose` not found on the server**
`sudo cat /var/log/bootstrap-docker.log` shows what user_data managed to install.
Re-running the Ansible `docker` role installs the plugin if it's missing.
