// Task 5 - Declarative Jenkins pipeline.
// Task 6 - `githubPush()` makes a push to main trigger this job automatically.
//
// Prerequisites in Jenkins:
//   * Credentials 'dockerhub-creds' -> Username with password
//       username = your Docker Hub user, password = a Docker Hub ACCESS TOKEN
//   * Plugins: Docker Pipeline, Git, GitHub, Pipeline: Stage View
//   * A Multibranch Pipeline or Pipeline-from-SCM job pointing at this repo

pipeline {
    agent any

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '5'))
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        skipDefaultCheckout(false)
    }

    triggers {
        // Task 6: fire on a GitHub push webhook.
        githubPush()
        // Fallback if the webhook cannot reach Jenkins (e.g. private network):
        // pollSCM('H/5 * * * *')
    }

    environment {
        REGISTRY       = 'docker.io'
        DOCKERHUB_NS   = 'instantprachi'
        IMAGE_NAME     = 'summerint-site'
        IMAGE_REPO     = "${REGISTRY}/${DOCKERHUB_NS}/${IMAGE_NAME}"
        DOCKER_CONTEXT = 'app'
        DOCKER_BUILDKIT = '1'
    }

    stages {

        stage('Checkout') {
            steps {
                // The job's SCM config supplies the GitHub repo; `checkout scm`
                // guarantees we build the exact commit that triggered the build.
                checkout scm
                script {
                    env.GIT_SHA     = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
                    env.GIT_BRANCH_NAME = env.BRANCH_NAME ?: sh(
                        script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG   = "${env.GIT_BRANCH_NAME.replaceAll('[^A-Za-z0-9._-]', '-')}-${env.GIT_SHA}"
                }
                echo "Building ${env.IMAGE_REPO}:${env.IMAGE_TAG} from ${env.GIT_BRANCH_NAME}"
            }
        }

        stage('Lint') {
            steps {
                sh '''
                    set -eu
                    test -f "${DOCKER_CONTEXT}/Dockerfile" || {
                      echo "Dockerfile missing at ${DOCKER_CONTEXT}/Dockerfile" >&2; exit 1; }
                    docker --version
                '''
            }
        }

        stage('Build image') {
            steps {
                script {
                    docker.build(
                        "${env.IMAGE_REPO}:${env.IMAGE_TAG}",
                        "--label org.opencontainers.image.revision=${env.GIT_SHA} " +
                        "--label org.opencontainers.image.source=${env.GIT_URL ?: ''} " +
                        "-f ${env.DOCKER_CONTEXT}/Dockerfile ${env.DOCKER_CONTEXT}"
                    )
                }
            }
        }

        stage('Smoke test image') {
            steps {
                sh '''
                    set -eu
                    CID=$(docker run -d -P "${IMAGE_REPO}:${IMAGE_TAG}")
                    trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT

                    PORT=$(docker port "$CID" 80/tcp | head -1 | sed 's/.*://')
                    echo "container ${CID} on host port ${PORT}"

                    for i in $(seq 1 20); do
                      if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
                        echo "image healthy"; exit 0
                      fi
                      sleep 2
                    done
                    echo "image failed its health check" >&2
                    docker logs --tail 50 "$CID" >&2
                    exit 1
                '''
            }
        }

        stage('Push to Docker Hub') {
            when {
                // Only publish from the mainline; PR/feature builds stop at the smoke test.
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH_NAME == 'main' }
                }
            }
            steps {
                script {
                    docker.withRegistry("https://${env.REGISTRY}", 'dockerhub-creds') {
                        def img = docker.image("${env.IMAGE_REPO}:${env.IMAGE_TAG}")
                        img.push()                       // immutable, traceable tag
                        img.push('latest')               // moving tag Watchtower follows
                        img.push("build-${env.BUILD_NUMBER}")
                    }
                }
                echo "Pushed ${env.IMAGE_REPO}:${env.IMAGE_TAG} (+ latest, build-${env.BUILD_NUMBER})"
            }
        }
    }

    post {
        always {
            sh '''
                # Never leave build images filling the agent's disk.
                docker rmi "${IMAGE_REPO}:${IMAGE_TAG}" >/dev/null 2>&1 || true
                docker image prune -f >/dev/null 2>&1 || true
            '''
        }
        success {
            echo "SUCCESS - ${env.IMAGE_REPO}:${env.IMAGE_TAG}"
        }
        failure {
            echo "FAILED - see the stage log above"
        }
        cleanup {
            cleanWs()
        }
    }
}
