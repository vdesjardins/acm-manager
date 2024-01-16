#!/usr/bin/env bash

set -e
set -o pipefail

gcloud builds submit . --project=corp-prod-gkeinfra -t gcr.io/corp-prod-gkeinfra/acm-manager:latest
podman pull gcr.io/corp-prod-gkeinfra/acm-manager:latest
podman tag gcr.io/corp-prod-gkeinfra/acm-manager:latest 491707178404.dkr.ecr.ca-central-1.amazonaws.com/acm-manager-test:latest

aws ecr get-login-password --region ca-central-1 | docker login --username AWS --password-stdin 491707178404.dkr.ecr.ca-central-1.amazonaws.com
podman push 491707178404.dkr.ecr.ca-central-1.amazonaws.com/acm-manager-test:latest
