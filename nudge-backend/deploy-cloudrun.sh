#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-nudge-backend}"
IMAGE="${IMAGE:-gcr.io/${PROJECT_ID}/${SERVICE_NAME}}"
SUPERMEMORY_API_KEY="${SUPERMEMORY_API_KEY:-}"
GROQ_API_KEY="${GROQ_API_KEY:-}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Error: set PROJECT_ID (e.g. export PROJECT_ID=my-gcp-project-id)"
  exit 1
fi

if [[ -z "${SUPERMEMORY_API_KEY}" || -z "${GROQ_API_KEY}" ]]; then
  echo "Error: set SUPERMEMORY_API_KEY and GROQ_API_KEY before deploy"
  exit 1
fi

echo "Using project: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"

gcloud run deploy "${SERVICE_NAME}" \
  --source . \
  --region "${REGION}" \
  --platform managed \
  --allow-unauthenticated \
  --port 8080 \
  --memory 512Mi \
  --cpu 1 \
  --concurrency 80 \
  --timeout 60 \
  --min-instances 0 \
  --max-instances 3 \
  --set-env-vars "SUPERMEMORY_API_KEY=${SUPERMEMORY_API_KEY},GROQ_API_KEY=${GROQ_API_KEY},NODE_ENV=production"

echo "Deployment complete."
