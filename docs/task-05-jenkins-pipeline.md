# Task 5 — Jenkins pipeline

> Create a Jenkinsfile (Declarative) that: Pulls code from GitHub. Builds Docker
> image. Pushes image to Docker Hub (use `instantprachi` namespace).

The pipeline lives at [`Jenkinsfile`](../Jenkinsfile) in the repository root.

## Stages

| Stage | Does |
|---|---|
| Checkout | `checkout scm` — the exact commit that triggered the build; derives `GIT_SHA` and a tag `<branch>-<sha>` |
| Lint | asserts `app/Dockerfile` exists and Docker is usable on the agent |
| Build image | `docker.build` of `app/`, labelled with the git revision |
| Smoke test image | runs the image, resolves the mapped port, polls `/healthz`, tears it down |
| Push to Docker Hub | **main only** — pushes `<branch>-<sha>`, `latest`, and `build-<n>` to `instantprachi/summerint-site` |

`post.always` removes the built image and prunes, so agents don't fill up;
`post.cleanup` wipes the workspace.

## Why three tags

- `main-a1b2c3d4e5f6` — immutable, tells you exactly what is running.
- `latest` — the moving tag Watchtower (Task 3) follows to auto-deploy.
- `build-42` — maps a running image back to a Jenkins build.

## One-time Jenkins setup

A ready-to-run controller is provided:

```bash
cp jenkins/.env.example jenkins/.env     # set JENKINS_URL
docker compose -f jenkins/docker-compose.yml up -d --build
docker exec summerint-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

It bundles the required plugins (`jenkins/plugins.txt`) and mounts the host
Docker socket so `docker.build` works inside the pipeline.

Then, in the UI:

1. **Manage Jenkins → Credentials → System → Global** → *Add Credentials*
   - Kind: **Username with password**
   - Username: your Docker Hub username
   - Password: a Docker Hub **access token** (Docker Hub → Account Settings →
     Personal access tokens) — not your account password
   - ID: **`dockerhub-creds`** ← the Jenkinsfile looks this ID up by name
2. **New Item → Multibranch Pipeline** (recommended) or **Pipeline**
   - Branch source: GitHub, pointing at your repo
   - Build configuration: *by Jenkinsfile*, script path `Jenkinsfile`
3. Push access: your Docker Hub user must be able to write to the
   `instantprachi` namespace (own it, or be a member of a team with write).

## Notes

- The push stage is gated on `main`, so feature branches and PRs get built and
  smoke-tested but never publish. Remove the `when` block to publish everywhere.
- `agent any` assumes the agent has the Docker CLI. The bundled controller does.
  If you use a different agent, either install the CLI there or switch to
  `agent { docker { image 'docker:27-cli' args '-v /var/run/docker.sock:/var/run/docker.sock' } }`.
- `disableConcurrentBuilds()` prevents two pushes racing on the same tag.
