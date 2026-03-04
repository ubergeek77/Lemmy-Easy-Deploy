#!/usr/bin/env bash
set -euo pipefail

# Make sure the upstream deployment hasn't changed
EXPECTED_COMMIT="721f7df"
echo "Checking for changes in lemmy-ansible templates/docker-compose.yml..."
LATEST_COMPOSE_COMMIT=$(
	curl -sf "https://api.github.com/repos/LemmyNet/lemmy-ansible/commits?path=templates/docker-compose.yml&per_page=1" |
		grep -m1 '"sha"' |
		sed 's/.*"sha": "\([^"]*\)".*/\1/'
)

if [[ -z "$LATEST_COMPOSE_COMMIT" ]]; then
	echo "ERROR: Could not fetch latest commit for lemmy-ansible templates/docker-compose.yml" >&2
	exit 1
fi

if [[ "$LATEST_COMPOSE_COMMIT" != "${EXPECTED_COMMIT}"* ]]; then
	echo "ERROR: lemmy-ansible templates/docker-compose.yml has changes after ${EXPECTED_COMMIT}." >&2
	echo "  Latest commit: ${LATEST_COMPOSE_COMMIT}" >&2
	echo "  Expected:      ${EXPECTED_COMMIT}" >&2
	exit 1
fi

echo "No upstream deployment changes."

get_latest_tag() {
	(
		WORKDIR=$(mktemp -d)
		cd ${WORKDIR}
		local repo_url="$1"
		local result

		git clone ${repo_url} ./

		result=$(
			git ls-remote --tags --sort=committerdate |
				cut -f2 |
				grep -v '\^{}' |
				sed 's|refs/tags/||' |
				grep -v -iE 'alpha|beta|rc' |
				grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
				tail -1
		)

		if [[ -z "$result" ]]; then
			echo "ERROR: No stable tags found for $repo_url" >&2
			exit 1
		fi

		echo "$result"
	)
}

LATEST_BACKEND=$(get_latest_tag "https://github.com/LemmyNet/lemmy")
LATEST_FRONTEND=$(get_latest_tag "https://github.com/LemmyNet/lemmy-ui")

echo "Detected versions:"
echo "   LATEST_BACKEND=${LATEST_BACKEND}"
echo "   LATEST_FRONTEND=${LATEST_FRONTEND}"

echo "LATEST_BACKEND=${LATEST_BACKEND}" >.backend_version
echo "LATEST_FRONTEND=${LATEST_FRONTEND}" >.frontend_version

echo "LATEST_BACKEND=${LATEST_BACKEND}" >>"$GITHUB_OUTPUT"
echo "LATEST_FRONTEND=${LATEST_FRONTEND}" >>"$GITHUB_OUTPUT"
