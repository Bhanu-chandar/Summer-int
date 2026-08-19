# Task 6 — GitHub → Jenkins webhook

> Connect GitHub with Jenkins via webhook. On code push to main, trigger the
> Jenkins job automatically.

Two halves: the **pipeline declares the trigger**, and **GitHub is told where to
POST**.

## 1. Pipeline side (already done)

[`Jenkinsfile`](../Jenkinsfile):

```groovy
triggers {
    githubPush()
}
```

> A Declarative `triggers` block only takes effect **after the job has run at
> least once** — Jenkins has to execute the Jenkinsfile to learn the trigger
> exists. Always build the job manually once before testing the webhook. This
> is the single most common reason "the webhook does nothing".

## 2. Jenkins side

1. **Manage Jenkins → System → Jenkins URL** — set it to the URL GitHub will
   reach, e.g. `http://<ec2-public-ip>:8080/`. If this is wrong or left as
   `localhost`, the plugin can misbehave.
2. Confirm the **GitHub plugin** is installed (it is, in `jenkins/plugins.txt`).
3. Leave *Manage Jenkins → System → GitHub → Advanced → Override Hook URL*
   unset unless you have a reason to change it.

The endpoint GitHub posts to is always:

```
http://<jenkins-host>:8080/github-webhook/      <-- trailing slash matters
```

## 3. Network side

Jenkins must be reachable **from GitHub's servers**, i.e. from the public
internet. Options:

**a) Open 8080 on the EC2 instance** (what this project does)

```hcl
# terraform/terraform.tfvars
jenkins_ingress_enabled = true
jenkins_allowed_cidrs = [
  "14.139.69.34/32",  # you (Jenkins UI)  <- update when your IP changes
  "192.30.252.0/22",  # GitHub hooks
  "185.199.108.0/22", # GitHub hooks
  "140.82.112.0/20",  # GitHub hooks
  "143.55.64.0/20",   # GitHub hooks
]
```

```bash
cd terraform && terraform apply
```

This deliberately does **not** open 8080 to `0.0.0.0/0`. A Jenkins controller
on the public internet is a well-known target, and the fresh-install setup
wizard is reachable before you have secured anything. The list above admits
only you and GitHub.

Two consequences worth knowing:

- **Your IP is dynamic on most connections.** When it changes you lose the UI
  (not the webhook). Re-run `curl -s https://api.ipify.org`, update the first
  entry, re-apply.
- **GitHub's ranges change occasionally.** If deliveries start timing out,
  refresh them: `curl -s https://api.github.com/meta | jq -r '.hooks[]'`.

**b) Local Jenkins? Tunnel it**

```bash
ngrok http 8080     # then use the https://xxxx.ngrok-free.app URL below
```

## 4. GitHub side

Repository → **Settings → Webhooks → Add webhook**

| Field | Value |
|---|---|
| Payload URL | `http://<jenkins-host>:8080/github-webhook/` |
| Content type | `application/json` |
| Secret | optional; if set, configure the same secret in Jenkins → System → GitHub Servers |
| SSL verification | enable it if Jenkins is behind HTTPS |
| Events | **Just the push event** |
| Active | checked |

GitHub immediately sends a `ping`. Open the webhook → **Recent Deliveries** and
confirm a green **200**.

## 5. Restricting to `main`

`githubPush()` fires for a push to *any* branch. Restrict in whichever way suits:

- **Multibranch Pipeline** (recommended): each branch is its own job, and the
  `Push to Docker Hub` stage is already gated with `when { branch 'main' }`, so
  non-main pushes build and test but never publish.
- **Single Pipeline job**: keep the SCM's *Branch Specifier* at `*/main` so only
  main is ever checked out.

## 6. Verify it

Without touching GitHub — probe reachability, then optionally fire a fake push:

```bash
./scripts/test-webhook.sh --url http://<ec2-ip>:8080
./scripts/test-webhook.sh --url http://<ec2-ip>:8080 \
    --repo https://github.com/Bhanu-chandar/Summer-int --simulate
```

Then the real thing:

```bash
git commit --allow-empty -m "test: trigger jenkins webhook"
git push origin main
```

Within a few seconds the job should start. Check, in order:

1. **GitHub → Settings → Webhooks → Recent Deliveries** — 200 means GitHub's
   part worked, and the problem (if any) is on the Jenkins side.
2. **Jenkins → Manage Jenkins → System Log** — GitHub plugin entries show the
   received hook.
3. **Job → Build History** — the build's cause should read
   *"Started by GitHub push by \<user\>"*.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Delivery 200, no build | Job hasn't run once yet, so the trigger isn't registered. Build manually. |
| Delivery 200, no build (2) | The job's configured Git URL doesn't match the payload's repo URL. They must be the same repo, and `https://` vs `git@` forms both work but the host/owner/name must match. |
| Delivery times out / 502 | Security group blocks 8080, or Jenkins isn't listening publicly. |
| Delivery 403 | CSRF/auth — make sure you're posting to `/github-webhook/` (with trailing slash), which is exempt, not to a job URL. |
| Delivery 404 | GitHub plugin missing. |
| Builds fire for every branch | Expected with `githubPush()`; see section 5. |
