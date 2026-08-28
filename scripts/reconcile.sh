#!/usr/bin/env bash
set -euo pipefail

[[ "$CANDIDATE" =~ ^[0-9a-f]{40}$ ]]
[[ "$PR" =~ ^[0-9]+$ ]]
git fetch --quiet origin main staging '+refs/heads/candidate:refs/remotes/origin/candidate' || git fetch --quiet origin main staging
pr=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR")
[[ $(jq -r '.head.sha' <<< "$pr") == "$CANDIDATE" ]]
[[ $(jq -r '.head.ref' <<< "$pr") == candidate ]]

reviews=$(gh api --paginate --slurp "repos/$GITHUB_REPOSITORY/pulls/$PR/reviews?per_page=100")
if ! jq -e --arg sha "$CANDIDATE" 'add | any(.[]; .state == "APPROVED" and .commit_id == $sha)' <<< "$reviews" >/dev/null; then
  echo 'exact candidate is not approved; no write'
  exit 0
fi

checks=$(gh api --paginate --slurp -H 'Accept: application/vnd.github+json' \
  "repos/$GITHUB_REPOSITORY/commits/$CANDIDATE/check-runs?per_page=100&filter=all")
latest=$(node scripts/select-latest-candidate-check.mjs "$CHECK_NAME" <<< "$checks")
jq -e '.status == "completed" and .conclusion == "success"' <<< "$latest" >/dev/null || {
  echo 'latest Candidate validation attempt is not successful; no write'
  exit 0
}

receipt=$(git show "$CANDIDATE:.candidate.json")
base=$(jq -er '.base' <<< "$receipt")
source=$(jq -er '.source' <<< "$receipt")
version=$(jq -er '.version' <<< "$receipt")
[[ $(git rev-parse "$CANDIDATE^") == "$source" ]]
production=$(git ls-remote origin refs/heads/main | awk '{print $1}')
candidate_tip=$(git ls-remote origin refs/heads/candidate | awk '{print $1}')
node scripts/verify-candidate-ref-state.mjs "$production" "$base" "$CANDIDATE" "$candidate_tip" <<< "$pr"

if [[ "$production" == "$base" ]]; then
  git push origin "$CANDIDATE:refs/heads/main"
  production=$CANDIDATE
  for _ in $(seq 1 30); do
    pr=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR")
    [[ $(jq -r '.state' <<< "$pr") == closed ]] && break
    sleep 1
  done
  [[ $(jq -r '.state' <<< "$pr") == closed ]]
  [[ $(jq -r '.merged' <<< "$pr") == true ]]
  [[ $(jq -r '.merge_commit_sha' <<< "$pr") == "$CANDIDATE" ]]
else
  [[ "$production" == "$CANDIDATE" ]]
fi

candidate_tip=$(git ls-remote origin refs/heads/candidate | awk '{print $1}')
node scripts/verify-candidate-ref-state.mjs "$production" "$base" "$CANDIDATE" "$candidate_tip" <<< "$pr"
[[ "${FAIL_AFTER:-}" != production ]] || { echo 'requested failure after Production Sync'; exit 1; }

tag="v$version"
tag_tip=$(git ls-remote origin "refs/tags/$tag" | awk '{print $1}')
if [[ -z "$tag_tip" ]]; then
  git push origin "$CANDIDATE:refs/tags/$tag"
else
  [[ "$tag_tip" == "$CANDIDATE" ]]
fi
[[ "${FAIL_AFTER:-}" != tag ]] || { echo 'requested failure after tag'; exit 1; }

if ! gh release view "$tag" >/dev/null 2>&1; then
  git show "$CANDIDATE:.release-notes.md" > /tmp/release-notes.md
  gh release create "$tag" --verify-tag --title "$tag" --notes-file /tmp/release-notes.md
fi
[[ "${FAIL_AFTER:-}" != release ]] || { echo 'requested failure after Release'; exit 1; }

git push origin "$CANDIDATE:refs/heads/staging"
[[ $(git ls-remote origin refs/heads/staging | awk '{print $1}') == "$CANDIDATE" ]]
