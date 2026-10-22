#!/usr/bin/env bash
# Starts an HCP Terraform speculative plan (a plan-only run) for the code in
# CONFIG_DIR, waits for it, and writes a short Markdown summary (resource
# counts + run link) to SUMMARY_FILE. It never prints the plan itself, the
# upload URL or log URLs: logs of a public repository are readable by anyone
# signed in to GitHub. The full plan stays in HCP Terraform.
#
# Required env: TF_API_TOKEN, TF_CLOUD_ORGANIZATION, TF_WORKSPACE
# Optional env: TF_HOSTNAME (default app.terraform.io), CONFIG_DIR (.),
#   RUN_MESSAGE, SUMMARY_FILE (plan-summary.md), POLL_SECONDS (10),
#   TIMEOUT_SECONDS (1800), TFC_API_URL and TFC_WEB_URL (tests only)
set -euo pipefail

: "${TF_API_TOKEN:?TF_API_TOKEN is not set}"
: "${TF_CLOUD_ORGANIZATION:?TF_CLOUD_ORGANIZATION is not set}"
: "${TF_WORKSPACE:?TF_WORKSPACE is not set}"
TF_HOSTNAME="${TF_HOSTNAME:-app.terraform.io}"
API="${TFC_API_URL:-https://${TF_HOSTNAME}/api/v2}"
WEB="${TFC_WEB_URL:-https://${TF_HOSTNAME}}"
CONFIG_DIR="${CONFIG_DIR:-.}"
RUN_MESSAGE="${RUN_MESSAGE:-Speculative plan from GitHub Actions}"
SUMMARY_FILE="${SUMMARY_FILE:-plan-summary.md}"
POLL_SECONDS="${POLL_SECONDS:-10}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1800}"

# Calls the HCP Terraform API. Usage: api METHOD PATH [JSON_BODY]
api() {
  local method=$1 path=$2 body=${3:-}
  local args=(--silent --show-error --fail-with-body --request "$method"
    --header "Authorization: Bearer ${TF_API_TOKEN}"
    --header "Content-Type: application/vnd.api+json")
  if [[ -n $body ]]; then args+=(--data "$body"); fi
  # Retry only reads, and only transient failures (HTTP 408/429/5xx, timeouts,
  # refused connections); curl honours Retry-After. POSTs are not retried, so
  # a retry can never create a second configuration version or run.
  if [[ $method == GET ]]; then args+=(--retry 5 --retry-connrefused --retry-max-time 120); fi
  curl "${args[@]}" "${API}${path}"
}

# Cancels the HCP Terraform run when the job is cancelled or the script times
# out, so an orphaned plan doesn't hold the Free plan's single concurrency slot.
cancel_run() {
  if [[ -n ${run_id:-} ]]; then
    api POST "/runs/${run_id}/actions/cancel" '{"comment":"GitHub job cancelled"}' >/dev/null 2>&1 || true
  fi
}
trap 'cancel_run; exit 130' INT TERM

# Sets a step output when running in GitHub Actions.
set_output() {
  if [[ -n ${GITHUB_OUTPUT:-} ]]; then echo "$1=$2" >> "$GITHUB_OUTPUT"; fi
}

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
past_deadline() { (( $(date +%s) >= deadline )); }

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# 1. Look up the workspace ID.
ws_id=$(api GET "/organizations/${TF_CLOUD_ORGANIZATION}/workspaces/${TF_WORKSPACE}" | jq -r '.data.id')
echo "Workspace: ${TF_CLOUD_ORGANIZATION}/${TF_WORKSPACE} (${ws_id})"

# 2. Package the configuration. The archive root must be the configuration root.
#    COPYFILE_DISABLE=1 stops macOS tar from adding "._*" metadata files
#    (Terraform would try to parse "._main.tf"); other systems ignore it.
COPYFILE_DISABLE=1 tar -czf "${workdir}/config.tar.gz" -C "$CONFIG_DIR" --exclude=.git --exclude=.terraform .

# 3. Create a speculative configuration version and upload the archive.
cv=$(api POST "/workspaces/${ws_id}/configuration-versions" \
  '{"data":{"type":"configuration-versions","attributes":{"auto-queue-runs":false,"speculative":true}}}')
cv_id=$(jq -r '.data.id' <<<"$cv")
upload_url=$(jq -r '.data.attributes."upload-url"' <<<"$cv")
unset cv
# The upload URL contains a secret. Mask it in case anything ever prints it.
if [[ -n ${GITHUB_ACTIONS:-} ]]; then echo "::add-mask::${upload_url}"; fi
curl --silent --show-error --fail-with-body --request PUT \
  --header "Content-Type: application/octet-stream" \
  --data-binary "@${workdir}/config.tar.gz" "$upload_url" >/dev/null
echo "Uploaded configuration version ${cv_id}"

# 4. Wait until HCP Terraform has processed the upload.
while :; do
  cv_status=$(api GET "/configuration-versions/${cv_id}" | jq -r '.data.attributes.status')
  case "$cv_status" in
    uploaded) break ;;
    errored) echo "::error::Configuration version ${cv_id} errored"; exit 1 ;;
  esac
  if past_deadline; then echo "::error::Timed out waiting for the configuration upload"; exit 1; fi
  sleep "$POLL_SECONDS"
done

# 5. Queue a plan-only run on exactly this configuration version.
run_body=$(jq -n --arg ws "$ws_id" --arg cv "$cv_id" --arg msg "$RUN_MESSAGE" '{
  data: {
    type: "runs",
    attributes: { "plan-only": true, message: $msg },
    relationships: {
      workspace: { data: { type: "workspaces", id: $ws } },
      "configuration-version": { data: { type: "configuration-versions", id: $cv } }
    }
  }
}')
run_id=$(api POST "/runs" "$run_body" | jq -r '.data.id')
run_url="${WEB}/app/${TF_CLOUD_ORGANIZATION}/workspaces/${TF_WORKSPACE}/runs/${run_id}"
echo "Run: ${run_url}"
set_output run_id "$run_id"
set_output run_url "$run_url"

# 6. Wait for a final status.
while :; do
  run=$(api GET "/runs/${run_id}")
  status=$(jq -r '.data.attributes.status' <<<"$run")
  case "$status" in
    planned_and_finished | errored | canceled | force_canceled | discarded | policy_soft_failed) break ;;
  esac
  if past_deadline; then status="timed_out"; cancel_run; break; fi
  echo "Status: ${status}"
  sleep "$POLL_SECONDS"
done
plan_id=$(jq -r '.data.relationships.plan.data.id // empty' <<<"$run")
unset run
echo "Final status: ${status}"

# 7. Read the resource counts (never the plan log).
add=0 change=0 destroy=0 import=0
if [[ -n $plan_id ]]; then
  counts=$(api GET "/plans/${plan_id}" | jq -r '.data.attributes |
    "\(."resource-additions" // 0) \(."resource-changes" // 0) \(."resource-destructions" // 0) \(."resource-imports" // 0)"')
  read -r add change destroy import <<<"$counts"
fi

# 8. Write the summary used for the PR comment and the job summary.
case "$status" in
  planned_and_finished) result="✅ Plan finished" ;;
  timed_out) result="⏱️ Timed out after ${TIMEOUT_SECONDS}s (the run was cancelled)" ;;
  *) result="❌ Plan ${status}" ;;
esac
{
  echo "<!-- tfc-speculative-plan -->"
  echo "### HCP Terraform speculative plan: \`${TF_WORKSPACE}\`"
  echo
  echo "| Result | Add | Change | Destroy | Import |"
  echo "|---|---|---|---|---|"
  echo "| ${result} | ${add} | ${change} | ${destroy} | ${import} |"
  echo
  echo "Full plan (organization members only): [${run_id}](${run_url})"
  echo
  echo "_The plan itself is not shown here: logs and comments of a public repository are visible to anyone signed in to GitHub._"
} > "$SUMMARY_FILE"
set_output summary_file "$SUMMARY_FILE"
set_output status "$status"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then cat "$SUMMARY_FILE" >> "$GITHUB_STEP_SUMMARY"; fi

[[ $status == planned_and_finished ]]
