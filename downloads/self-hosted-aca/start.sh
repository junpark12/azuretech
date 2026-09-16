#!/usr/bin/env bash
set +x
set -euo pipefail
umask 077

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

for name in GITHUB_APP_ID GITHUB_APP_INSTALLATION_ID GITHUB_APP_PRIVATE_KEY GITHUB_OWNER; do
    [[ -n "${!name:-}" ]] || fail "Missing required environment variable: ${name}"
done
[[ "$GITHUB_APP_ID" =~ ^[0-9]+$ ]] || fail "GITHUB_APP_ID must be a numeric App ID."
[[ "$GITHUB_APP_INSTALLATION_ID" =~ ^[0-9]+$ ]] || fail "GITHUB_APP_INSTALLATION_ID must be numeric."
[[ "$GITHUB_OWNER" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || fail "Invalid GITHUB_OWNER."

RUNNER_SCOPE="${RUNNER_SCOPE:-repo}"
RUNNER_LABELS="${RUNNER_LABELS:-container-app}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"
case "$RUNNER_SCOPE" in
    org)
        RUNNER_URL="https://github.com/${GITHUB_OWNER}"
        REGISTRATION_PATH="orgs/${GITHUB_OWNER}/actions/runners/registration-token"
        GROUP_ARGS=(--runnergroup "$RUNNER_GROUP")
        ;;
    repo)
        [[ -n "${GITHUB_REPO:-}" ]] || fail "GITHUB_REPO is required for repository scope."
        [[ "$GITHUB_REPO" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "Invalid GITHUB_REPO."
        [[ "$GITHUB_REPO" != "." && "$GITHUB_REPO" != ".." ]] || fail "Invalid GITHUB_REPO."
        RUNNER_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
        REGISTRATION_PATH="repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/registration-token"
        GROUP_ARGS=()
        ;;
    *) fail "RUNNER_SCOPE must be org or repo." ;;
esac

for tool in curl jq openssl date tr hostname; do
    command -v "$tool" >/dev/null || fail "Required executable is missing: ${tool}"
done
cd /home/runner/actions-runner
[[ -x ./config.sh && -x ./run.sh ]] || fail "Runner distribution is missing."

b64url() {
    openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

# Do not print API response bodies: successful responses contain credentials.
request_token() {
    local path="$1" credential="$2" stage="$3" response status body token
    if ! response=$(curl --silent --show-error --fail \
        --connect-timeout 15 --max-time 60 --request POST \
        --header "Authorization: Bearer ${credential}" \
        --header "Accept: application/vnd.github+json" \
        --header "X-GitHub-Api-Version: 2022-11-28" \
        --write-out $'\n%{http_code}' \
        "https://api.github.com/${path}"); then
        fail "${stage} request failed; check HTTP status, network, clock, and App permissions."
    fi
    status="${response##*$'\n'}"
    body="${response%$'\n'*}"
    [[ "$status" == "201" ]] || fail "${stage} returned an unexpected HTTP status (${status})."
    if ! token=$(printf '%s' "$body" | jq -er '.token | select(type == "string" and length > 0)' 2>/dev/null); then
        fail "${stage} response did not contain a nonempty token."
    fi
    [[ "$token" != *$'\n'* && "$token" != *$'\r'* ]] || fail "${stage} returned an invalid token."
    printf '%s' "$token"
}

printf '%s\n' "Creating a short-lived GitHub App JWT."
NOW=$(date +%s)
IAT=$((NOW - 60))
EXP=$((NOW + 540))
HEADER=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
PAYLOAD=$(printf '{"iat":%s,"exp":%s,"iss":"%s"}' "$IAT" "$EXP" "$GITHUB_APP_ID" | b64url)
UNSIGNED="${HEADER}.${PAYLOAD}"
if ! SIGNATURE=$(printf '%s' "$UNSIGNED" | openssl dgst -sha256 \
    -sign <(printf '%s' "$GITHUB_APP_PRIVATE_KEY") 2>/dev/null | b64url); then
    fail "JWT signing failed; verify the private key and its PEM formatting."
fi
JWT="${UNSIGNED}.${SIGNATURE}"
INSTALL_TOKEN=$(request_token "app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens" "$JWT" "Installation token")
REG_TOKEN=$(request_token "$REGISTRATION_PATH" "$INSTALL_TOKEN" "Runner registration token")

# Reduce credentials inherited by workflow child processes; this is not a trust boundary.
unset GITHUB_APP_PRIVATE_KEY JWT INSTALL_TOKEN SIGNATURE UNSIGNED PAYLOAD HEADER
printf '%s\n' "Registering one ephemeral runner."
./config.sh --unattended \
    --name "runner-$(hostname)" \
    --url "$RUNNER_URL" \
    --token "$REG_TOKEN" \
    "${GROUP_ARGS[@]}" \
    --ephemeral \
    --labels "$RUNNER_LABELS"
unset REG_TOKEN
printf '%s\n' "Starting the runner."
exec ./run.sh
