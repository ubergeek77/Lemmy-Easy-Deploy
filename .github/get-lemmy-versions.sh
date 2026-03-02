#!/usr/bin/env bash
set -euo pipefail

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
