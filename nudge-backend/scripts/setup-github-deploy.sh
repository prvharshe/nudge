#!/usr/bin/env bash
# One-time setup: create a GCP deploy SA and store GCP_SA_KEY in GitHub Actions secrets.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-msaas-438006}"
SA_NAME="${SA_NAME:-github-nudge-deploy}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
REPO="${REPO:-prvharshe/nudge}"
KEY_FILE="$(mktemp -t nudge-gcp-sa-XXXXXX.json)"

cleanup() { rm -f "${KEY_FILE}"; }
trap cleanup EXIT

echo "Project: ${PROJECT_ID}"
echo "Service account: ${SA_EMAIL}"
echo "Repo: ${REPO}"

gcloud config set project "${PROJECT_ID}"

if ! gcloud iam service-accounts describe "${SA_EMAIL}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name="GitHub Actions Nudge backend deploy"
fi

for ROLE in \
  roles/run.admin \
  roles/iam.serviceAccountUser \
  roles/cloudbuild.builds.editor \
  roles/artifactregistry.writer \
  roles/storage.admin
do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet >/dev/null
  echo "Granted ${ROLE}"
done

gcloud iam service-accounts keys create "${KEY_FILE}" --iam-account="${SA_EMAIL}"
gh secret set GCP_SA_KEY --repo "${REPO}" < "${KEY_FILE}"
echo "Stored GitHub secret GCP_SA_KEY"

if [[ -f "$(dirname "$0")/../.env" ]]; then
  # shellcheck disable=SC1091
  set -a && source "$(dirname "$0")/../.env" && set +a
  if [[ -n "${SUPERMEMORY_API_KEY:-}" ]]; then
    printf '%s' "${SUPERMEMORY_API_KEY}" | gh secret set SUPERMEMORY_API_KEY --repo "${REPO}"
    echo "Stored GitHub secret SUPERMEMORY_API_KEY"
  fi
  if [[ -n "${GROQ_API_KEY:-}" ]]; then
    printf '%s' "${GROQ_API_KEY}" | gh secret set GROQ_API_KEY --repo "${REPO}"
    echo "Stored GitHub secret GROQ_API_KEY"
  fi
fi

echo "Done. Push a nudge-backend change to main (or run workflow_dispatch) to deploy."
