#!/usr/bin/env bash

LED_CURRENT_VERSION="1.3.3"

# cd to the directory the script is in
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd $SCRIPT_DIR

load_env() {
	if [[ ! -f ./config.env ]]; then
		return 1
	fi

	# Source the config file
	source ./config.env

	# Check if we have an old environment variable from the previous version of Lemmy-Easy-Deploy
	known_old=("BUILD_FROM_SOURCE" "TLS_ENABLED" "LEMMY_NOREPLY_DISPLAY" "LEMMY_NOREPLY_FROM" "USE_EMAIL")
	declare -a old_vars
	for var in "${known_old[@]}"; do
		if [[ -n "${!var}" ]]; then
			old_vars+=("$var")
		fi
	done

	# Check if we DON'T have a new environment variable from this version of Lemmy-Easy-Deploy
	known_new=("SMTP_TLS_TYPE" "LEMMY_TLS_ENABLED" "SMTP_SERVER" "SMTP_PORT" "SMTP_NOREPLY_DISPLAY" "SMTP_NOREPLY_FROM" "ENABLE_POSTFIX" "ENABLE_EMAIL")
	declare -a new_vars
	for var in "${known_new[@]}"; do
		if [[ -z "${!var}" ]]; then
			new_vars+=("$var")
		fi
	done

	# Check if we have old vars
	# Ignore this warning if just running diagnostics
	if [[ "${RUN_DIAG}" != "1" ]]; then
		if [[ ${#old_vars[@]} -gt 0 ]]; then
			echo
			echo "-------------------------------------------------------------------------------------------"
			echo "| !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!!"
			echo "|"
			echo "| You have variables from an old version of Lemmy-Easy-Deploy that are no longer used:"
			# Loop over the array elements and print them line by line
			for var in "${old_vars[@]}"; do
				echo "| * $var"
			done
			echo "|"
			echo "| Please update your config.env based on the latest config.env.example"
			echo "|"
			echo "| Here's how:"
			echo "|"
			echo "| 1. Make a backup of your settings:"
			echo "|       cp ./config.env ./config.bak"
			echo "|"
			echo "| 2. Make a new config file based on the template: "
			echo "|       cp ./config.env.example ./config.env"
			echo "|"
			echo "| 3. Manually edit config.env, and refer to config.bak for any old settings you had"
			echo "|"
			echo "| --> This deployment may have unexpected behavior until you do this! <--"
			echo "|"
			echo "-------------------------------------------------------------------------------------------"
			if ! ask_user "Do you want to continue regardless?"; then
				exit 0
			fi
			echo
		fi

		# Check if we are missing new vars
		if [[ ${#new_vars[@]} -gt 0 ]]; then
			echo
			echo "-------------------------------------------------------------------------------------------"
			echo "| !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!!"
			echo "|"
			echo "| You are missing variables that were introduced in an update to Lemmy-Easy-Deploy"
			# Loop over the array elements and print them line by line
			for var in "${new_vars[@]}"; do
				echo "| * $var"
			done
			echo "|"
			echo "| Please update your config.env based on the latest config.env.example"
			echo "|"
			echo "| Here's how:"
			echo "|"
			echo "| 1. Make a backup of your settings:"
			echo "|       cp ./config.env ./config.bak"
			echo "|"
			echo "| 2. Make a new config file based on the template: "
			echo "|       cp ./config.env.example ./config.env"
			echo "|"
			echo "| 3. Manually edit config.env, and refer to config.bak for any old settings you had"
			echo "|"
			echo "| --> This deployment may have unexpected behavior until you do this! <--"
			echo "|"
			echo "-------------------------------------------------------------------------------------------"
			if ! ask_user "For these missing settings, the default values will be used. Do you want to continue?"; then
				exit 0
			fi
			echo
		fi
	fi

	# Make sure nothing is missing
	# We omit SMTP_LOGIN and SMTP_PASSWORD to allow for anonymous logins
	LEMMY_HOSTNAME="${LEMMY_HOSTNAME:-example.com}"
	SETUP_SITE_NAME="${SETUP_SITE_NAME:-Lemmy}"
	SETUP_ADMIN_USER="${SETUP_ADMIN_USER:-lemmy}"
	CADDY_DISABLE_TLS="${CADDY_DISABLE_TLS:-false}"
	CADDY_HTTP_PORT="${CADDY_HTTP_PORT:-80}"
	CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT:-443}"
	LEMMY_TLS_ENABLED="${LEMMY_TLS_ENABLED:-true}"
	ENABLE_EMAIL="${ENABLE_EMAIL:-false}"
	SMTP_SERVER="${SMTP_SERVER:-postfix}"
	SMTP_PORT="${SMTP_PORT:-25}"
	SMTP_NOREPLY_DISPLAY="${SMTP_NOREPLY_DISPLAY:-Lemmy NoReply}"
	SMTP_NOREPLY_FROM="${SMTP_NOREPLY_FROM:-noreply@${LEMMY_HOSTNAME}}"
	SMTP_TLS_TYPE="${SMTP_TLS_TYPE:-none}"
	ENABLE_POSTFIX="${ENABLE_POSTFIX:-false}"
	POSTGRES_POOL_SIZE="${POSTGRES_POOL_SIZE:-5}"

}

# Check if the system's hostname is problematic or not
hostname_valid() {
	if [[ -f /etc/hostname ]]; then
		SYSTEM_HOSTNAME="$(cat /etc/hostname | sed -e 's| ||g' | tr -d '\n')"
		if [[ "${SYSTEM_HOSTNAME}" == "${LEMMY_HOSTNAME}" ]]; then
			return 1
		fi
	fi
	return 0
}

diag_info() {
	set +e
	load_env
	echo ""
	echo "==== Docker Information ===="
	detect_runtime
	echo "==== System Information ===="
	OS_FMT="$(uname -s)"
	if [[ "${OS_FMT}" != "Linux" ]]; then
		OS_FMT="${OS_FMT} (unsupported)"
	fi
	echo "      OS: ${OS_FMT}"
	echo "  KERNEL: $(uname -r) ($(uname -m))"
	HOSTNAME_FMT="OK"
	if ! hostname_valid; then
		HOSTNAME_FMT="BAD"
	fi
	echo "HOSTNAME: ${HOSTNAME_FMT}"
	SHELL_FMT="$(ps -o pid,comm | grep $$ | rev | cut -d' ' -f 1 | rev)"
	if [[ "$?" != "0" ]]; then
		SHELL_FMT="$SHELL **(ps unavailable)"
	fi

	echo "   SHELL: $(detect_shell)"
	echo "  MEMORY:"
	if ! command -v free &>/dev/null; then
		echo "*** 'free' command unavailable ***"
	else
		echo "$(free -h)"
	fi
	echo ""
	echo "DISTRO:"
	echo "----------------------------"
	if [[ ! -f "/etc/os-release" ]]; then
		echo "*** /etc/os-release not found ***"
	else
		cat /etc/os-release | grep --color=never NAME
	fi
	echo "----------------------------"
	echo ""
	echo "==== Lemmy-Easy-Deploy Information ===="
	echo "Version: $LED_CURRENT_VERSION"
	echo ""
	docker ps --filter "name=lemmy-easy-deploy" --format "table {{.Image}}\t{{.RunningFor}}\t{{.Status}}"
	echo ""
	echo "Integrity:"
	if ! command -v sha256sum &>/dev/null; then
		echo "   *** 'sha256sum' command unavailable"
	else
		echo "    $(sha256sum $0)"
		for f in ./templates/*; do
			echo "    $(sha256sum $f)"
		done
	fi
	echo ""
	echo "Custom Files: "
	if [[ ! -d "./custom" ]] || [ -z "$(ls -A ./custom)" ]; then
		echo "*** No custom files ***"
	else
		ls -lhn ./custom
	fi
	echo ""
	echo "==== Settings ===="
	if [[ ! -f "./config.env" ]]; then
		echo "*** config.env not found ***"
	else
		if [[ -n "${CF_API_TOKEN}" ]]; then
			USES_CLOUDFLARE="Yes"
		else
			USES_CLOUDFLARE="No"
		fi
		echo "        CLOUDFLARE: ${USES_CLOUDFLARE}"
		echo " CADDY_DISABLE_TLS: ${CADDY_DISABLE_TLS}"
		echo "   CADDY_HTTP_PORT: ${CADDY_HTTP_PORT}"
		echo "  CADDY_HTTPS_PORT: ${CADDY_HTTPS_PORT}"
		echo " LEMMY_TLS_ENABLED: ${LEMMY_TLS_ENABLED}"
		echo "      ENABLE_EMAIL: ${ENABLE_EMAIL}"
		echo "         SMTP_PORT: ${SMTP_PORT}"
		echo "    ENABLE_POSTFIX: ${ENABLE_POSTFIX}"
		echo "POSTGRES_POOL_SIZE: ${POSTGRES_POOL_SIZE}"
	fi
	echo ""
	echo "==== Generated Files ===="
	if [[ ! -d "./live" ]] || [ -z "$(ls -A ./live)" ]; then
		echo "*** No files generated ***"
	else
		if [[ -f ./live/version ]]; then
			DEPLOY_VERSION="$(cat ./live/version)"
		else
			DEPLOY_VERSION="(not deployed)"
		fi
		echo "Deploy Version: ${DEPLOY_VERSION}"
		echo ""
		ls -lhn ./live/
	fi
	echo ""
}

get_service_status() {
	# Do this check in a loop in case Docker Compose is unreachable
	# Can happen on slow systems
	# If the stack ultimately cannot be contacted, show status as UNREACHABLE
	# Run in a subshell where we cd to ./live first
	# Some Docker distributions don't like only having the stack name and "need" to be in the same directory
	(
		cd ./live
		loop_n=0
		while [ $loop_n -lt 10 ]; do
			unset CONTAINER_ID
			unset SVC_STATUS
			loop_n=$((loop_n + 1))
			CONTAINER_ID="$($COMPOSE_CMD -p "lemmy-easy-deploy" ps -q $1)"
			if [ $? -ne 0 ]; then
				sleep 5
				continue
			fi
			SVC_STATUS="$(echo $CONTAINER_ID | xargs docker inspect --format='{{ .State.Status }}')"
			if [ $? -ne 0 ]; then
				sleep 5
				continue
			fi
			if [[ -z "${SVC_STATUS}" ]]; then
				sleep 5
				continue
			fi
			break
		done
		if [[ -z "${SVC_STATUS}" ]]; then
			echo "UNREACHABLE"
		else
			echo "$SVC_STATUS"
		fi
	)
}

random_string() {
	length=32
	string=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "$length" | head -n 1)
	echo "$string"
}

detect_runtime() {
	# Check for docker or podman
	for cmd in "podman" "docker"; do
		if $cmd >/dev/null 2>&1; then
			RUNTIME_CMD=$cmd
			break
		fi
	done

	if [[ -z "${RUNTIME_CMD}" ]]; then
		echo >&2 "ERROR: Could not find a container runtime. Did you install Docker?"
		echo >&2 "Please click on your server distribution in the list here, then follow the installation instructions:"
		echo >&2 "     https://docs.docker.com/engine/install/#server"
		exit 1
	fi

	# Check for docker compose or podman compose
	if [[ "${RUNTIME_CMD}" == "podman" ]]; then
		echo "WARNING: podman will probably work, but I haven't tested it much. It's up to you to make sure all the permissions for podman are correct!"
		COMPOSE_CMD="podman-compose"
		if $COMPOSE_CMD >/dev/null 2>&1; then
			COMPOSE_FOUND="true"
		else
			echo >&2 "ERROR: podman detected, but podman-compose is not installed. Please install podman-compose!"
			exit 1
		fi
	else
		for cmd in "docker compose" "docker-compose"; do
			COMPOSE_CMD="${cmd}"
			if $COMPOSE_CMD >/dev/null 2>&1; then
				COMPOSE_FOUND="true"
				break
			fi
		done
	fi

	if [[ "${COMPOSE_FOUND}" != "true" ]]; then
		echo >&2 "ERROR: Could not find Docker Compose. Is Docker Compose installed?"
		echo >&2 "Please click on your server distribution in the list here, then follow the installation instructions:"
		echo >&2 "     https://docs.docker.com/engine/install/#server"
		exit 1
	fi

	# Grab the runtime versions:
	DOCKER_VERSION="$($RUNTIME_CMD --version | head -n 1)"
	DOCKER_MAJOR="$(echo ${DOCKER_VERSION#*version } | cut -d '.' -f 1 | tr -cd '[:digit:]')"
	COMPOSE_VERSION="$($COMPOSE_CMD version | head -n 1)"
	COMPOSE_MAJOR="$(echo ${COMPOSE_VERSION#*version } | cut -d '.' -f 1 | tr -cd '[:digit:]')"

	echo "Detected runtime: $RUNTIME_CMD (${DOCKER_VERSION})"
	echo "Detected compose: $COMPOSE_CMD (${COMPOSE_VERSION})"

	RUNTIME_STATE="ERROR"
	if docker run --rm -v "$(pwd):/host:ro" hello-world >/dev/null 2>&1; then
		RUNTIME_STATE="OK"
	fi
	echo "   Runtime state: $RUNTIME_STATE"
	echo ""

	# Warn if using an unsupported Docker version
	if ((DOCKER_MAJOR < 20)); then
		echo "-----------------------------------------------------------------------"
		echo "WARNING: Your version of Docker is outdated and unsupported."
		echo ""
		echo "Only Docker Engine versions 20 and up are supported by Docker Inc:"
		echo "    https://endoflife.date/docker-engine"
		echo ""
		echo "The deployment will likely work regardless, but if you run into issues,"
		echo "please install the official version of Docker before filing an issue:"
		echo "    https://docs.docker.com/engine/install/"
		echo ""
		echo "-----------------------------------------------------------------------"
	fi

	# Warn if using an unsupported Compose version
	if ((COMPOSE_MAJOR < 2)); then
		echo "-----------------------------------------------------------------------"
		echo "WARNING: Your version of Docker Compose is outdated and unsupported."
		echo ""
		echo "Docker Compose v2 has been Generally Available (GA) for over 1 year,"
		echo "and as of June 2023, Docker Compose v1 has been officially deprecated"
		echo "by Docker Inc."
		echo ""
		echo "https://www.docker.com/blog/new-docker-compose-v2-and-v1-deprecation/"
		echo ""
		echo "Popular Linux distributions, such as Debian and Ubuntu, are still distributing"
		echo "outdated and unofficial packages of Docker and Docker Compose."
		echo ""
		echo "However, those packages are neither supported nor endorsed by Docker Inc."
		echo ""
		echo "Lemmy-Easy-Deploy might still work regardless, but testing is only done"
		echo "with Docker Compose v2. Compose v1 is not supported."
		echo ""
		echo "For the best experience, please install the official version of Docker:"
		echo "    https://docs.docker.com/engine/install/"
		echo ""
		echo "-----------------------------------------------------------------------"
	fi

}

display_help() {
	echo "Usage:"
	echo "  $0 [options]"
	echo ""
	echo "Run with no options to check for Lemmy updates and deploy them, and/or restart a stopped deployment."
	echo ""
	echo "Options:"
	echo "  -s|--shutdown          Shut down a running Lemmy-Easy-Deploy deployment (does not delete data)"
	echo "  -l|--lemmy-tag <tag>   Install a specific version of the Lemmy Backend"
	echo "  -w|--webui-tag <tag>   Install a specific version of the Lemmy WebUI (will use value from --lemmy-tag if missing)"
	echo "  -f|--force-deploy      Skip the update checks and force (re)deploy the latest/specified version (must use this for rc versions!)"
	echo "  -r|--rebuild           Deploy from source, don't update the Git repos, and deploy them as-is, implies -f and ignores -l/-w"
	echo "  -y|--yes               Answer Yes to any prompts asking for confirmation"
	echo "  -v|--version           Prints the current version of Lemmy-Easy-Deploy"
	echo "  -u|--update            Update Lemmy-Easy-Deploy"
	echo "  -d|--diag              Dump diagnostic information for issue reporting, then exit"
	echo "  -h|--help              Show this help message"
	exit 1
}

print_version() {
	echo ${LED_CURRENT_VERSION:?}
}

self_update() {
	# Check for LED updates
	LED_UPDATE_CHECK="$(latest_github_tag ubergeek77/Lemmy-Easy-Deploy)"

	# Make sure both strings are trackable
	if ! is_version_string "${LED_CURRENT_VERSION}" || ! is_version_string "${LED_UPDATE_CHECK}"; then
		echo "ERROR: Could not determine upgrade path for ${LED_CURRENT_VERSION} --> ${LED_UPDATE_CHECK}"
		exit 1
	fi

	# Check if this version is newer
	if [[ "$(compare_versions ${LED_CURRENT_VERSION} ${LED_UPDATE_CHECK})" != "1" ]]; then
		echo "No update available."
		exit 0
	else
		if [[ "${UPDATE_FROM_PROMPT}" != "1" ]]; then
			echo ""
			echo "--> Update available! (${LED_UPDATE_CHECK})"
		fi
	fi

	if [[ ! -d "./.git" ]]; then
		echo >&2 "ERROR: The local .git folder for Lemmy-Easy-Deploy was not found."
		echo >&2 "Self-updates are only available if you cloned this repo with git clone:"
		echo >&2 "   git clone https://github.com/ubergeek77/Lemmy-Easy-Deploy"
		exit 1
	fi

	print_update_error() {
		echo >&2 "ERROR: Update failed. Have you modified Lemmy-Easy-Deploy?"
		echo >&2 "You can try to reset Lemmy-Easy-Deploy manually, but you will lose any changes you made!"
		echo >&2 "Back up any foreign files you may have in this directory, then run these commands:"
		echo >&2 "    git reset --hard"
		echo >&2 "    $0 --update"
		echo >&2 "If you did not do anything special with your installation, and are confused by this message, please report this:"
		echo >&2 "    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issues"
	}

	echo "--> Installing Lemmy-Easy-Deploy ${LED_UPDATE_CHECK}..."
	echo "-----------------------------------------------------------"
	if ! git checkout main; then
		print_update_error
		exit 1
	fi
	if ! git pull; then
		print_update_error
		exit 1
	fi
	if ! git fetch --tags --force; then
		print_update_error
		exit 1
	fi
	if ! git checkout ${LED_UPDATE_CHECK}; then
		print_update_error
		exit 1
	fi
	echo "-----------------------------------------------------------"
	echo ""
	echo "Update complete! Version ${LED_UPDATE_CHECK} installed."
	echo ""
	exit 0
}

# Validate if an input is in 0.0.0 format
is_version_string() {
	[[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

compare_versions() {
	IFS='.' read -ra fields <<<"$1"
	_major=${fields[0]}
	_minor=${fields[1]}
	_micro=${fields[2]}
	LEFT_VERSION_NUMERIC=$((_major * 10000 + _minor * 1000 + _micro))

	IFS='.' read -ra fields <<<"$2"
	_major=${fields[0]}
	_minor=${fields[1]}
	_micro=${fields[2]}
	RIGHT_VERSION_NUMERIC=$((_major * 10000 + _minor * 1000 + _micro))

	if ((LEFT_VERSION_NUMERIC < RIGHT_VERSION_NUMERIC)); then
		echo "1"
	else
		echo "0"
	fi
}

latest_github_tag() {
	# Use a github token if supplied
	unset CURL_ARGS
	if [[ -n "${GITHUB_TOKEN}" ]]; then
		CURL_ARGS="-H \"Authorization: Bearer ${GITHUB_TOKEN}\""
	fi
	ratelimit_error='"message":"API rate limit exceeded for'
	RESPONSE="$(curl -s ${CURL_ARGS} https://api.github.com/repos/$1/releases/latest)"
	if [[ "${RESPONSE,,}" == *"${ratelimit_error,,}"* ]]; then
		echo >&2 ""
		echo >&2 "---------------------------------------------------------------------"
		echo >&2 "ERROR: GitHub API Rate Limit exceeded. Cannot check latest tag for $1"
		echo >&2 ""
		echo >&2 "Please do not report this as an issue. If you are on a cloud server,"
		echo >&2 "a VM neighbor likely exhausted the rate limit. Please try again later."
		echo >&2 "---------------------------------------------------------------------"
		echo >&2 ""
		exit 1
	fi
	RESULT=$(echo "${RESPONSE}" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

	# If no result, check the latest tag that doesn't contain the words beta, alpha, or rc
	if [[ -z "${RESULT}" ]]; then
		RESPONSE="$(curl -s ${CURL_ARGS} https://api.github.com/repos/$1/git/refs/tags)"
		while IFS= read -r line; do
			if [[ "${line,,}" != *beta* && "${line,,}" != *alpha* && "${line,,}" != *rc* ]]; then
				RESULT="$(echo ${line} | cut -d'/' -f3 | tr -d '",')"
				break
			fi
		done <<<$(echo "${RESPONSE}" | grep '"ref":' | tac)
	fi

	# If still no result, then it probably doesn't exist
	if [[ -z "${RESULT}" ]]; then
		echo >&2 ""
		echo >&2 "---------------------------------------------------------------------"
		echo >&2 "ERROR: No tags found for $1"
		echo >&2 ""
		echo >&2 "Did the repo move?"
		echo >&2 "---------------------------------------------------------------------"
		echo >&2 ""
		exit 1
	fi
	echo "${RESULT}"
}

ask_user() {
	prompt="${1} [Y/n] "

	# Always answer yes if the user specified -y
	if [ "${ANSWER_YES}" = "1" ]; then
		echo "$prompt Y"
		return 0
	fi

	while true; do
		printf "%s" "$prompt"
		read answer

		case "$(echo "$answer" | tr '[:upper:]' '[:lower:]')" in
		y | yes | "")
			return 0
			;;
		n | no)
			return 1
			;;
		*)
			echo ""
			echo "Invalid input. Please enter Y for yes or N for no."
			;;
		esac
	done
}

check_image_arch() {
	# If this is an unsupported version of Docker, we can't check the normal way
	# Docker versions <24 do not support checking images that have attestation tags
	if ((DOCKER_MAJOR < 24)); then
		echo "WARNING: Unsupported Docker version; pulling full image first"
		if docker pull "$1" >/dev/null 2>&1; then
			return 0
		else
			return 1
		fi
	fi

	# Detect the current docker architecture
	if [[ -z "${DOCKER_ARCH}" ]]; then
		export DOCKER_ARCH="$(docker version --format '{{.Server.Arch}}')"
		export SEARCH_ARCH="${DOCKER_ARCH}"
	fi

	# Determine if imagetools is available
	if [[ -z "${IMAGETOOLS_AVAILABLE}" ]]; then
		if docker buildx imagetools >/dev/null 2>&1; then
			export IMAGETOOLS_AVAILABLE=1
		else
			export IMAGETOOLS_AVAILABLE=0
		fi
	fi

	# Determine how to inspect the manifest
	if [[ "${IMAGETOOLS_AVAILABLE}" == "1" ]]; then
		# If the arch is just arm, search for arm/v7
		if [[ "${DOCKER_ARCH}" == "arm" ]]; then
			SEARCH_ARCH="arm/v7"
		fi
		INSPECT_CMD="docker buildx imagetools"
		INSPECT_MATCH="Platform:    linux/${SEARCH_ARCH}$"
	else
		INSPECT_CMD="docker manifest"
		INSPECT_MATCH="\"architecture\": \"${DOCKER_ARCH}\",$"
	fi

	# Get the manifest info
	MANIFEST=$($INSPECT_CMD inspect "$1" 2>&1)

	# Handle non existent images
	if echo "$MANIFEST" | grep -iEq 'failed|unauthorized|manifest unknown|no such manifest|not found|error'; then
		return 1
	fi

	# Handle single-arch images
	if ! echo "$MANIFEST" | grep -Eq 'Platform|"architecture"'; then
		echo "! No reported architecture for $1; assuming linux/amd64"
		if [[ "${DOCKER_ARCH}" == "amd64" ]]; then
			return 0
		else
			return 1
		fi
	fi

	# Search for this system's architecture
	if echo "$MANIFEST" | grep -q "${INSPECT_MATCH}"; then
		return 0
	else
		return 1
	fi
}

# Shut down a deployment
shutdown_deployment() {
	cd ./live
	$COMPOSE_CMD -p "lemmy-easy-deploy" down
}

# Detect if the user is using any custom files, copy them if needed,
# and modify the docker-compose.yml to use them
install_custom_env() {
	if [[ -f ./custom/customCaddy.env ]]; then
		echo "--> Found customCaddy.env; passing custom environment variables to 'proxy'"
		sed -i -e 's|{{ CADDY_EXTRA_ENV }}|./customCaddy.env|g' ./live/docker-compose.yml
		cp ./custom/customCaddy.env ./live
	else
		sed -i '/{{ CADDY_EXTRA_ENV }}/d' ./live/docker-compose.yml
	fi

	if [[ -f ./custom/customLemmy.env ]]; then
		echo "--> Found customLemmy.env; passing custom environment variables to 'lemmy'"
		sed -i -e 's|{{ LEMMY_EXTRA_ENV }}|./customLemmy.env|g' ./live/docker-compose.yml
		cp ./custom/customLemmy.env ./live

		# Warn the user if they have changed CADDY_HTTP_PORT or CADDY_HTTPS_PORT but have not set LEMMY_CORS_ORIGIN
		# Test in a subshell to not mess with any environment variables
		(
			source ./custom/customLemmy.env
			if [[ -z "${LEMMY_CORS_ORIGIN}" ]]; then
				if [[ "${CADDY_HTTP_PORT}" != "80" ]] || [[ "${CADDY_HTTPS_PORT}" != "443" ]]; then
					echo ""
					echo "----------------------------------------------------------------------------------------------------"
					echo "WARNING: You have changed one or more ports used by Caddy, but have not specified LEMMY_CORS_ORIGIN"
					echo "This may result in your instance throwing errors and becoming unusable."
					echo ""
					echo "To fix this, create the file './custom/customLemmy.env', and put the following inside of it:"
					echo "    LEMMY_CORS_ORIGIN=http://<your-domain>:<custom-port>"
					echo ""
					echo "Change the protocol, domain, and port as needed."
					echo "----------------------------------------------------------------------------------------------------"
					echo ""
				fi
			fi
		)

	else
		sed -i '/{{ LEMMY_EXTRA_ENV }}/d' ./live/docker-compose.yml
	fi

	if [[ -f ./custom/customLemmy-ui.env ]]; then
		echo "--> Found customLemmy-ui.env; passing custom environment variables to 'lemmy-ui'"
		sed -i -e 's|{{ LEMMY_UI_EXTRA_ENV }}|./customLemmy-ui.env|g' ./live/docker-compose.yml
		cp ./custom/customLemmy-ui.env ./live
	else
		sed -i '/{{ LEMMY_UI_EXTRA_ENV }}/d' ./live/docker-compose.yml
	fi

	if [[ -f ./custom/customPictrs.env ]]; then
		echo "--> Found customPictrs.env; passing custom environment variables to 'pictrs'"
		sed -i -e 's|{{ PICTRS_EXTRA_ENV }}|./customPictrs.env|g' ./live/docker-compose.yml
		cp ./custom/customPictrs.env ./live
	else
		sed -i '/{{ PICTRS_EXTRA_ENV }}/d' ./live/docker-compose.yml
	fi

	if [[ -f ./custom/customPostgres.env ]]; then
		echo "--> Found customPostgres.env; passing custom environment variables to 'postgres'"
		sed -i -e 's|{{ POSTGRES_EXTRA_ENV }}|./customPostgres.env|g' ./live/docker-compose.yml
		cp ./custom/customPostgres.env ./live
	else
		sed -i '/{{ POSTGRES_EXTRA_ENV }}/d' ./live/docker-compose.yml
	fi

	if [[ -f ./custom/customPostfix.env ]]; then
		echo "--> Found customPostfix.env; passing custom environment variables to 'postfix'"
		sed -i -e 's|{{ POSTFIX_EXTRA_ENV }}|./customPostfix.env|g' ./live/docker-compose.yml
		cp ./custom/customPostfix.env ./live
	else
		sed -i '/{{ POSTFIX_EXTRA_ENV }}/d' ./live/docker-compose.yml
	fi

	if [[ -f ./custom/customPostgresql.conf ]]; then
		echo "--> Found customPostgresql.conf; overriding default 'postgresql.conf'"
		sed -i -e 's|{{ POSTGRES_CONF }}|./customPostgresql.conf:/var/lib/postgresql/data/postgresql.conf|g' ./live/docker-compose.yml
		cp ./custom/customPostgresql.conf ./live
	else
		sed -i '/{{ POSTGRES_CONF }}/d' ./live/docker-compose.yml
	fi
}

# Detect the current shell
detect_shell() {
	# Get the current shell
	# If for some reason ps fails, we can make an educated guess on $SHELL
	DETECTED_SHELL=$(ps -o pid,comm | grep $$ | rev | cut -d' ' -f 1 | rev)
	if [ "$?" != "0" ]; then
		DETECTED_SHELL="$SHELL"
	fi
	echo "${DETECTED_SHELL}"
}

# Do compatibility checks
check_compatibility() {
	DETECTED_SHELL=$(detect_shell)

	# Make sure the user is using bash
	case "${DETECTED_SHELL}" in
	*bash) ;;
	*)
		echo ""
		echo "|--------------------------------------------------------------------------------------------------"
		echo "|    !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! !!! WARNING !!! WARNING !!!"
		echo "|"
		echo "| This shell is not Bash. Lemmy-Easy-Deploy is a Bash script that uses features of Bash."
		echo "|"
		echo "| The current shell has been detected to be: '${DETECTED_SHELL}'"
		echo "|"
		echo "| If you continue, this script is very likely to break, as it is not compatible with other shells."
		echo "|"
		echo "| You have the option to proceed anyway, but this could create a broken deployment, or the script"
		echo "| could behave in unexpected ways. You have been warned."
		echo "|--------------------------------------------------------------------------------------------------"
		echo ""
		if ! ask_user "Proceed with this unsupported shell?"; then
			exit 0
		fi
		;;
	esac

	# Check for non-Linux systems (i.e. macos)
	DETECTED_OS="$(uname -s)"
	if [[ "${DETECTED_OS,,}" != "linux" ]]; then
		echo ""
		echo "|--------------------------------------------------------------------------------------------------|"
		echo "|    !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! !!! WARNING !!! WARNING !!!   |"
		echo "|                                                                                                  |"
		echo "| This system is not a Linux system. You appear to have a \"${DETECTED_OS}\" system.               |"
		echo "|                                                                                                  |"
		echo "| Lemmy-Easy-Deploy is intended for use on Linux systems only, and the images it deploys are built |"
		echo "| specifically for Linux platforms.                                                                |"
		echo "|                                                                                                  |"
		echo "| Unfortunately, compatibility on other systems, especially macOS (Darwin), cannot be guaranteed.  |"
		echo "|                                                                                                  |"
		echo "| You have the option to proceed anyway, but this could create a broken deployment, the script     |"
		echo "| could behave in unexpected ways, or the deployment might not start at all. You have been warned. |"
		echo "|--------------------------------------------------------------------------------------------------|"
		echo ""
		if ! ask_user "Proceed on this unsupported OS?"; then
			exit 0
		fi
	fi

	# Check for binaries we absolutely need
	REQUIRED_CMDS=("cat" "curl" "sed" "grep" "tr" "cp")
	for c in "${REQUIRED_CMDS[@]}"; do
		if ! command -v "$c" >/dev/null 2>&1; then
			echo >&2 "------------------------------------------------------"
			echo >&2 "FATAL ERROR: This system does not have the $c command."
			echo >&2 "This script cannot proceed without it.                "
			echo >&2 "------------------------------------------------------"
			exit 1
		fi
	done
}

# Exit on error
set -e

# parse arguments
while (("$#")); do
	case "$1" in
	-s | --shutdown)
		RUN_SHUTDOWN=1
		shift 1
		;;
	-l | --lemmy-tag)
		if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
			BACKEND_TAG_OVERRIDE="$2"
			# Let the user specify a git tag to build from source manually
			if [[ "${BACKEND_TAG_OVERRIDE,,}" == git:* ]]; then
				BACKEND_TAG_OVERRIDE="${BACKEND_TAG_OVERRIDE#"git:"}"
				BUILD_BACKEND=1
			fi
			shift 2
		else
			echo >&2 "ERROR: Argument for $1 is missing"
			exit 1
		fi
		;;
	-w | --webui-tag)
		if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
			FRONTEND_TAG_OVERRIDE="$2"
			# Let the user specify a git tag to build from source manually
			if [[ "${FRONTEND_TAG_OVERRIDE,,}" == git:* ]]; then
				FRONTEND_TAG_OVERRIDE="${FRONTEND_TAG_OVERRIDE#"git:"}"
				BUILD_FRONTEND=1
			fi
			shift 2
		else
			echo >&2 "ERROR: Argument for $1 is missing"
			exit 1
		fi
		;;
	-f | --force-deploy)
		FORCE_DEPLOY=1
		echo
		echo "WARNING: Force deploying; this will regenerate configs and deploy again even if there were no updates"
		echo "Passwords will NOT be re-generated"
		echo
		shift 1
		;;
	-r | --rebuild)
		REBUILD_SOURCE=1
		FORCE_DEPLOY=1
		BUILD_BACKEND=1
		BUILD_FRONTEND=1
		shift 1
		;;
	-y | --yes)
		ANSWER_YES=1
		shift 1
		;;
	-v | --version)
		RUN_PRINT_VERSION=1
		shift 1
		;;
	-u | --update)
		RUN_SELF_UPDATE=1
		shift 1
		;;
	-d | --diag)
		RUN_DIAG=1
		shift 1
		;;
	-h | --help)
		DISPLAY_HELP=1
		shift 1
		;;
	*)
		echo >&2 "Unrecognized arguments: $@"
		echo
		display_help
		exit 1
		;;
	esac
done

# Do what the user wanted after parsing arguments, so order doesn't matter
if [[ "${DISPLAY_HELP}" == "1" ]]; then
	display_help
	exit 0
fi

if [[ "${RUN_PRINT_VERSION}" == "1" ]]; then
	print_version
	exit 0
fi

if [[ "${RUN_SHUTDOWN}" == "1" ]]; then
	detect_runtime
	shutdown_deployment
	exit 0
fi

if [[ "${RUN_DIAG}" == "1" ]]; then
	diag_info
	exit 0
fi

if [[ "${RUN_SELF_UPDATE}" == "1" ]]; then
	self_update
	exit 0
fi

# Check the current system for compatibility
check_compatibility

# Check for LED updates
LED_UPDATE_CHECK="$(latest_github_tag ubergeek77/Lemmy-Easy-Deploy)"

# Check if this version is newer
if [[ "$(compare_versions ${LED_CURRENT_VERSION} ${LED_UPDATE_CHECK})" == "1" ]]; then
	echo
	echo "===================================================="
	echo "|     A Lemmy-Easy-Deploy update is available!     |"
	echo "|                 ${LED_CURRENT_VERSION} --> ${LED_UPDATE_CHECK}                  |"
	echo "==================================================="
	echo
	# Exclude update from unattended yes answers
	if [[ "${ANSWER_YES}" != "1" ]]; then
		if ask_user "Would you like to cancel the current operation and install the update now?"; then
			UPDATE_FROM_PROMPT=1
			self_update
			exit 0
		fi
	fi
fi

# Warn user if they are using --rebuild incorrectly
if [[ "${REBUILD_SOURCE}" == "1" ]] && [[ -n "${BACKEND_TAG_OVERRIDE}" ]]; then
	echo
	echo "WARNING: --rebuild specified, but a --lemmy-tag override has been provided (${BACKEND_TAG_OVERRIDE})"
	echo "If the sources do not already exist, this version will be checked out, but it will be ignored otherwise"
	echo
fi

if [[ "${REBUILD_SOURCE}" == "1" ]] && [[ -n "${FRONTEND_TAG_OVERRIDE}" ]]; then
	echo
	echo "WARNING: --rebuild specified, but a --webui-tag override has been provided (${FRONTEND_TAG_OVERRIDE})"
	echo "If the sources do not already exist, this version will be checked out, but it will be ignored otherwise"
	echo
fi

# If a frontend override wasn't specified, but a backend one was, match the versions
if [[ -z "${FRONTEND_TAG_OVERRIDE}" ]] && [[ -n "${BACKEND_TAG_OVERRIDE}" ]]; then
	FRONTEND_TAG_OVERRIDE="${BACKEND_TAG_OVERRIDE}"
	BUILD_FRONTEND="${BUILD_BACKEND}"
fi

echo "========================================"
echo "Lemmy-Easy-Deploy by ubergeek77 (v${LED_CURRENT_VERSION})"
echo "========================================"
echo ""
detect_runtime

# If the runtime state is bad, we can't continue
if [[ "${RUNTIME_STATE}" != "OK" ]]; then
	echo >&2 "----------------------------------------------------------------------------------------"
	echo >&2 "ERROR: Failed to run Docker."
	echo >&2 ""
	echo >&2 "Something is wrong with your Docker installation."
	echo >&2 ""
	echo >&2 "Possible fixes:"
	echo >&2 "    * Add your user to the 'docker' group (recommended)"
	echo >&2 "    * Reboot or re-log after adding your user to the 'docker' group"
	echo >&2 "    * Run this script with sudo (try the 'docker' group method first)"
	echo >&2 "    * Docker is not running or is not enabled (systemctl enable docker && systemctl start docker) "
	echo >&2 "    * Reboot your machine after installing Docker for the first time"
	echo >&2 ""
	echo >&2 "Please ensure you can run the following command on your own without errors:"
	echo >&2 "    docker run --rm -v "\$\(pwd\):/host:ro" hello-world"
	echo >&2 ""
	echo >&2 "If you see any errors while running that command, please Google the error messages"
	echo >&2 "to see if any of the solutions work for you. Once Docker is functional on your system,"
	echo >&2 "you can try running Lemmy-Easy-Deploy again."
	echo >&2 "----------------------------------------------------------------------------------------"
	echo >&2 ""
	exit 1
fi

# Yell at the user if they didn't follow instructions
if [[ ! -f "./config.env" ]]; then
	echo >&2 "ERROR: ./config.env not found! Did you copy the example config?"
	echo "    Try: cp ./config.env.example ./config.env"
	exit 1
fi

load_env

# Yell at the user if they didn't follow instructions, again
if [[ -z "$LEMMY_HOSTNAME" ]] || [[ "$LEMMY_HOSTNAME" == "example.com" ]]; then
	echo >&2 "ERROR: You did not set your hostname in config.env! Do it like this:"
	echo >&2 "LEMMY_HOSTNAME=example.com"
	exit 1
fi
if [[ $LEMMY_HOSTNAME =~ ^https?: ]]; then
	echo >&2 "ERROR: Don't put http/https in config.env! Do it like this:"
	echo >&2 "LEMMY_HOSTNAME=example.com"
	exit 1
fi

# Check for config oddities

# If the hostname matches the Lemmy hostname, there will be problems
if ! hostname_valid; then
	echo ""
	echo "---------------------------------------------------------------------------------------------------"
	echo "WARNING: The hostname of this server matches the hostname you chose for Lemmy."
	echo ""
	echo "Your Lemmy server will be unable to resolve itself to a real IP, and will instead"
	echo "use the IP '127.0.1.1' everywhere '${LEMMY_HOSTNAME}' is referenced."
	echo ""
	echo "If you upload an icon or banner to your instance, those images will not load."
	echo ""
	echo "In Lemmy-UI 0.18.0 and up, having an icon will cause a **Fatal Server Error** and your instance will be unusable."
	echo ""
	echo "It is HIGHLY RECOMMENDED that you change the hostname of your server before deploying."
	echo "You can look up how to do this on your own, but if you are on Ubuntu, this link may help:"
	echo "    https://www.cyberciti.biz/faq/ubuntu-change-hostname-command/"
	echo ""
	echo "Don't forget to **reboot your machine** after changing the hostname."
	echo "---------------------------------------------------------------------------------------------------"
	echo ""
	echo "If you continue right now, your instance may become inoperable."
	if ! ask_user "Do you want to continue regardless?"; then
		exit 0
	fi
fi

# If email is enabled, the postfix service is disabled, and the server is postfix,
# warn the user
if [[ "${ENABLE_EMAIL}" == "1" ]] || [[ "${ENABLE_EMAIL}" == "true" ]]; then
	if [[ "${ENABLE_POSTFIX}" != "1" ]] && [[ "${ENABLE_POSTFIX}" != "true" ]]; then
		if [[ "${SMTP_SERVER}" == "postfix" ]]; then
			echo
			echo "WARNING: You have enabled email, but the postfix service is not enabled, and"
			echo "you have not changed the variable SMTP_SERVER from the default value of 'postfix'"
			echo
			echo "If you are trying to use the embedded postfix service, set ENABLE_POSTFIX to 'true'"
			echo
			echo "If you are trying to use an external SMTP service, please set these variables:"
			echo "* SMTP_TLS_TYPE"
			echo "* SMTP_LOGIN"
			echo "* SMTP_PASSWORD"
			echo
			if ! ask_user "Do you want to continue regardless?"; then
				exit 0
			fi
		fi
	fi
fi

# If this system has any of the volume names with the live prefix, they probably started the deployment manually
VOLUME_CHECK=("live_caddy_config" "live_caddy_data" "live_pictrs_data" "live_postgres_data")
VOLUME_LIST="$(docker volume ls | tr '\n' ' ')"
DETECTED_VOLUMES=()

for v in "${VOLUME_CHECK[@]}"; do
	if [[ $VOLUME_LIST == *"$v"* ]]; then
		DETECTED_VOLUMES+=("$v")
	fi
done

if [ ${#DETECTED_VOLUMES[@]} -gt 0 ]; then
	echo ""
	echo "|-----------------------------------------------------------------------"
	echo "|    !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!!"
	echo "|"
	echo "| There are one or more Docker volumes on this system that might belong"
	echo "| to a misconfigured Lemmy-Easy-Deploy stack:"
	echo "|"
	for d in "${DETECTED_VOLUMES[@]}"; do
		echo "| * $d"
	done
	echo "|"
	echo "| It is very likely that you navigated to the ./live folder, and manually"
	echo "| ran '$COMPOSE_CMD up' without specifying a project/stack name with '-p'"
	echo "|"
	echo "| If you continue, it is highly likely that the deployment you are about"
	echo "| to launch will conflict with this misconfigured one."
	echo "|"
	echo "| It is highly recommended to do the following:"
	echo "| * Shut down the stack:"
	echo "|     cd ./live"
	echo "|     $COMPOSE_CMD down"
	echo "|"
	echo "| * Rename your Docker volumes by following this guidance:"
	echo "|    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issues/28#issuecomment-1622698074"
	echo "|"
	echo "| * Manage the deployment with ./deploy.sh"
	echo "|------------------------------------------------------------------------"
	echo ""
	if ! ask_user "Do you want to continue anyway?"; then
		exit 0
	fi
fi

# Read the user's current versions of Lemmy
if [[ -f "./live/version" ]]; then
	VERSION_STRING="$(cat ./live/version)"

	IFS=';' read -ra parts <<<"$VERSION_STRING"
	CURRENT_BACKEND="${parts[0]}"
	CURRENT_FRONTEND="${parts[1]}"

	# Lemmy-Easy-Deploy backwards compatibility
	if [[ -z "${CURRENT_FRONTEND}" ]]; then
		CURRENT_FRONTEND="${CURRENT_BACKEND}"
	fi
else
	CURRENT_BACKEND="0.0.0"
	CURRENT_FRONTEND="0.0.0"
fi

# Detect if the user has an existing postgres volume
if docker volume ls | grep -q lemmy-easy-deploy_postgres_data 2>&1 >/dev/null; then
	HAS_VOLUME=1
else
	HAS_VOLUME=0
fi

# Warn if the user is missing the credential files, but volumes exist
if [[ "${HAS_VOLUME}" == "1" ]]; then
	if [[ ! -f "./live/lemmy.env" ]] || [[ ! -f "./live/pictrs.env" ]] || [[ ! -f "./live/postgres.env" ]]; then
		echo ""
		echo "|-----------------------------------------------------------------------|"
		echo "|    !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!!    |"
		echo "|                                                                       |"
		echo "| You do not currently have a deployment tracked by Lemmy-Easy-Deploy,  |"
		echo "| but data volumes for Lemmy already exist.                             |"
		echo "|                                                                       |"
		echo "| If you continue, Lemmy-Easy-Deploy will generate new credentials      |"
		echo "| for this deployment, but they will not match the credentials used     |"
		echo "| in the data volumes that exist. You will be unable to log in.         |"
		echo "|                                                                       |"
		echo "|                THIS DEPLOYMENT IS VERY LIKELY TO FAIL!                |"
		echo "|                                                                       |"
		echo "| You are probably trying to do a clean deployment. However,            |"
		echo "| deleting the ./live folder is not enough. Lemmy's data is stored      |"
		echo "| in named Docker volumes in the Docker system directory.               |"
		echo "|                                                                       |"
		echo "| To list the volumes used by Lemmy-Easy-Deploy, run:                   |"
		echo "|            docker volume ls | grep \"lemmy-easy-deploy_\"               |"
		echo "|                                                                       |"
		echo "| To delete one of those volumes, run:                                  |"
		echo "|            docker volume rm <name-of-the-volume>                      |"
		echo "|                                                                       |"
		echo "| Please be careful when deleting volumes!                              |"
		echo "| Do not delete data you want to keep!                                  |"
		echo "-------------------------------------------------------------------------"
		echo ""
		if ! ask_user "Do you want to continue regardless?"; then
			exit 0
		fi
	fi
fi

# Warn if the user has a currently tracked version, but volumes do not exist
if [[ "${CURRENT_BACKEND}" != "0.0.0" ]] && [[ "${HAS_VOLUME}" == "0" ]]; then
	echo "|-----------------------------------------------------------------------|"
	echo "|    !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!!    |"
	echo "|                                                                       |"
	echo "| You have a deployment tracked by Lemmy-Easy-Deploy,                   |"
	echo "| but a data volume for Lemmy does not exist.                           |"
	echo "|                                                                       |"
	echo "| If you are trying to migrate your installation from another machine,  |"
	echo "| copying the ./live folder is not enough. Lemmy's data is stored       |"
	echo "| in named Docker volumes in the Docker system directory.               |"
	echo "|                                                                       |"
	echo "| In that case, you will need to migrate those named volumes over to    |"
	echo "| this machine before continuing. Lemmy-Easy-Deploy cannot currently    |"
	echo "| do this for you automatically, but there may be a feature to do so    |"
	echo "| in the future.                                                        |"
	echo "|                                                                       |"
	echo "| If you continue, any credentials and settings that have already been  |"
	echo "| generated will be used again, but the Lemmy instance you deploy will  |"
	echo "| be a \"brand new\" one. Otherwise, this deployment should work fine.    |"
	echo "|                                                                       |"
	echo "| If deploy.sh does not start Lemmy from this state, you may need to    |"
	echo "| run deploy.sh with the -f flag to force-redeploy.                     |"
	echo "|                                                                       |"
	echo "| Otherwise, to start over with a fresh deployment, it is recommended   |"
	echo "| to clear the ./live folder. But please be careful!                    |"
	echo "|                                                                       |"
	echo "| Do not delete data you want to keep!                                  |"
	echo "-------------------------------------------------------------------------"
	echo ""
	if ! ask_user "Do you want to continue regardless?"; then
		exit 0
	fi
fi
echo

# Determine Backend update version
# Allow the user to override the version to update to

LATEST_BACKEND="${BACKEND_TAG_OVERRIDE}"
if [[ -z "${LATEST_BACKEND}" ]]; then
	LATEST_BACKEND="$(latest_github_tag LemmyNet/lemmy)"
fi

if [[ "${CURRENT_BACKEND}" != "0.0.0" ]]; then
	echo " Current Backend Version: ${CURRENT_BACKEND:?}"
fi

if [[ "${REBUILD_SOURCE}" == "1" ]]; then
	echo "  Target Backend Version: Local Git Repo"
elif [[ -n "${BACKEND_TAG_OVERRIDE}" ]]; then
	echo "  Target Backend Version: ${LATEST_BACKEND} (Manual)"
elif [[ "${BUILD_BACKEND}" == "1" ]]; then
	echo "  Target Backend Version: (git:${LATEST_BACKEND})"
else
	echo "  Latest Backend Version: ${LATEST_BACKEND}"
fi
echo

# Determine backend upgrade path
if [[ "${FORCE_DEPLOY}" != "1" ]] && [[ "${BUILD_BACKEND}" != "1" && "${REBUILD_SOURCE}" != "1" ]]; then

	backend_versions=("${CURRENT_BACKEND}" "${LATEST_BACKEND}")
	for v in "${backend_versions[@]}"; do
		if ! is_version_string $v; then
			echo >&2 ""
			echo >&2 "-----------------------------------------------------------------------------------------------------------"
			echo >&2 "ERROR: Unable to determine Backend upgrade path. One of the below versions is not in 0.0.0 format:"
			echo >&2 "   Installed Backend: ${CURRENT_BACKEND}"
			echo >&2 "      Target Backend: ${LATEST_BACKEND}"
			echo >&2 ""
			echo >&2 "Are you trying to install an \"rc\" version manually? Combine the -l flag with -f to skip the version check:"
			echo >&2 "        $0 -l <some-tag> -f"
			echo >&2 ""
			echo >&2 "Did you previously install a git or \"rc\" version? Use the -f flag to return to the latest stable version:"
			echo >&2 "        $0 -f"
			echo >&2 ""
			echo >&2 "If you did not do anything special with your installation, and are confused by this message, please report this:"
			echo >&2 "    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issues"
			echo "-----------------------------------------------------------------------------------------------------------"
			exit 1
		fi
	done
	# Check if an update is available
	BACKEND_OUTDATED="$(compare_versions ${CURRENT_BACKEND} ${LATEST_BACKEND})"
else
	BACKEND_OUTDATED=1
fi

# Determine Frontend update version
# Allow the user to override the version to update to
LATEST_FRONTEND="${FRONTEND_TAG_OVERRIDE}"
if [[ "${LATEST_FRONTEND}" == "" ]]; then
	LATEST_FRONTEND="$(latest_github_tag LemmyNet/lemmy-ui)"
fi

if [[ "${CURRENT_FRONTEND}" != "0.0.0" ]]; then
	echo " Current Frontend Version: ${CURRENT_FRONTEND:?}"
fi

if [[ "${REBUILD_SOURCE}" == "1" ]]; then
	echo "  Target Frontend Version: Local Git Repo"
elif [[ -n "${FRONTEND_TAG_OVERRIDE}" ]]; then
	echo "  Target Frontend Version: ${LATEST_FRONTEND} (Manual)"
elif [[ "${BUILD_BACKEND}" == "1" ]]; then
	echo "  Target Frontend Version: (git:${LATEST_FRONTEND})"
else
	echo "  Latest Frontend Version: ${LATEST_FRONTEND}"
fi
echo

# Determine Frontend upgrade path
if [[ "${FORCE_DEPLOY}" != "1" ]] && [[ "${BUILD_FRONTEND}" != "1" && "${REBUILD_SOURCE}" != "1" ]]; then
	frontend_versions=("${CURRENT_FRONTEND}" "${LATEST_FRONTEND}")
	for v in "${frontend_versions[@]}"; do
		if ! is_version_string $v; then
			echo >&2 "-----------------------------------------------------------------------------------------------------------"
			echo >&2 "ERROR: Unable to determine Frontend upgrade path. One of the below versions is not in 0.0.0 format:"
			echo >&2 "   Installed Frontend: ${CURRENT_FRONTEND}"
			echo >&2 "      Target Frontend: ${LATEST_FRONTEND}"
			echo >&2 ""
			echo >&2 "Are you trying to install an \"rc\" version manually? Combine the -w flag with -f to skip the version check:"
			echo >&2 "        $0 -w <some-tag> -f"
			echo >&2 ""
			echo >&2 "Did you previously install a git or \"rc\" version? Use the -f flag to return to the latest stable version:"
			echo >&2 "        $0 -f"
			echo >&2 ""
			echo >&2 "If you did not do anything special with your installation, and are confused by this message, please report this:"
			echo >&2 "    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issues"
			echo "-----------------------------------------------------------------------------------------------------------"
			exit 1
		fi
	done
	# Check if an update is available
	FRONTEND_OUTDATED="$(compare_versions ${CURRENT_FRONTEND} ${LATEST_FRONTEND})"
else
	FRONTEND_OUTDATED=1
fi

if [[ "${FORCE_DEPLOY}" != "1" ]]; then
	if [[ "${CURRENT_BACKEND}" != "0.0.0" ]] && [[ "${BACKEND_OUTDATED}" == "1" ]]; then
		echo "A Backend update is available!"
		echo "   BE: ${CURRENT_BACKEND} --> ${LATEST_BACKEND}"
		echo
	fi

	if [[ "${CURRENT_FRONTEND}" != "0.0.0" ]] && [[ "${FRONTEND_OUTDATED}" == "1" ]]; then
		echo "A Frontend update is available!"
		echo "   FE: ${CURRENT_FRONTEND} --> ${LATEST_FRONTEND}"
		echo
	fi
fi

# Warn the user to check their file before deploying
if [[ -f ./custom/docker-compose.yml.template ]]; then
	echo ""
	echo "NOTE: You are currently overriding the built-in docker-compose.yml with your own template."
	echo "      Please remember to incorporate any new changes into your docker-compose.yml.template before deploying!"
	echo ""
fi

# Ask the user if they want to update
if [[ "${BACKEND_OUTDATED}" == "1" ]] || [[ "${FRONTEND_OUTDATED}" == "1" ]]; then
	# Print scary warning if this is a backend update and data exists
	if [[ "${HAS_VOLUME}" == "1" ]] && [[ "${CURRENT_BACKEND}" != "${LATEST_BACKEND}" ]]; then
		echo "--------------------------------------------------------------------|"
		echo "|  !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!!  |"
		echo "|                                                                   |"
		echo "| Updates to the Lemmy Backend perform a database migration!        |"
		echo "|                                                                   |"
		echo "| This process is **generally safe and does not risk data loss.**   |"
		echo "|                                                                   |"
		echo "| However, if you update, but run into a new bug/issue,             |"
		echo "| you will NOT be able to roll back to the previous version!        |"
		echo "| You will be stuck with the bug/issue until an update is released. |"
		echo "|                                                                   |"
		echo "|              LEMMY BACKEND UPDATES ARE ONE-WAY ONLY               |"
		echo "|                                                                   |"
		echo "| THIS IS YOUR ONLY OPPORTUNITY TO MAKE A BACKUP OF YOUR LEMMY DATA |"
		echo "|                                                                   |"
		echo "| Lemmy data is stored in Docker Volumes, **NOT** the ./live folder |"
		echo "|                                                                   |"
		echo "| Please consult the Docker docs for commands on making a backup:   |"
		echo "|    https://docs.docker.com/storage/volumes/#back-up-a-volume      |"
		echo "|                                                                   |"
		echo "| The most important Volume to back up is named:                    |"
		echo "|       lemmy-easy-deploy_postgres_data                             |"
		echo "|                                                                   |"
		echo "|    (Lemmy-Easy-Deploy may automate this process in the future)    |"
		echo "|                                                                   |"
		echo "|  !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!!  |"
		echo "|-------------------------------------------------------------------|"
		echo
	fi
	# Change prompt depending on the situation
	PROMPT_STRING="Would you like to deploy this update?"
	if [[ "${CURRENT_BACKEND}" == "0.0.0" ]] && [[ "${CURRENT_FRONTEND}" == "0.0.0" ]]; then
		PROMPT_STRING="Ready to deploy?"
	elif [[ "${CURRENT_BACKEND}" == "${LATEST_BACKEND}" ]] && [[ "${CURRENT_FRONTEND}" == "${LATEST_FRONTEND}" ]]; then
		PROMPT_STRING="Re-deploy these versions?"
	fi
	if ! ask_user "${PROMPT_STRING:?}"; then
		exit 0
	fi
else
	echo "No updates available."
	echo ""
	echo "Ensuring deployment is running..."
	echo ""
	cd ./live
	$COMPOSE_CMD -p "lemmy-easy-deploy" up --no-recreate -d
	exit 0
fi

# Define the template locations
CADDY_DOCKERFILE_TEMPLATE="./templates/Caddy-Dockerfile.template"
CADDYFILE_TEMPLATE="./templates/Caddyfile.template"
CLOUDFLARE_SNIP="./templates/cloudflare.snip"
COMPOSE_EMAIL_SNIP="./templates/compose-email.snip"
COMPOSE_EMAIL_VOLUMES_SNIP="./templates/compose-email-volumes.snip"
COMPOSE_TEMPLATE="./templates/docker-compose.yml.template"
LEMMY_EMAIL_SNIP="./templates/lemmy-email.snip"
LEMMY_HJSON_TEMPLATE="./templates/lemmy.hjson.template"

# Load custom templates if they exist
if [[ -d ./custom ]]; then
	if [[ -f ./custom/Caddy-Dockerfile.template ]]; then
		echo "--> Using custom 'Caddy-Dockerfile.template'"
		CADDY_DOCKERFILE_TEMPLATE="./custom/Caddy-Dockerfile.template"
	fi
	if [[ -f ./custom/Caddyfile.template ]]; then
		echo "--> Using custom 'Caddyfile.template'"
		CADDYFILE_TEMPLATE="./custom/Caddyfile.template"
	fi
	if [[ -f ./custom/cloudflare.snip ]]; then
		echo "--> Using custom 'cloudflare.snip'"
		CLOUDFLARE_SNIP="./custom/cloudflare.snip"
	fi
	if [[ -f ./custom/compose-email.snip ]]; then
		echo "--> Using custom 'compose-email.snip'"
		COMPOSE_EMAIL_SNIP="./custom/compose-email.snip"
	fi
	if [[ -f ./custom/compose-email-volumes.snip ]]; then
		echo "--> Using custom 'compose-email-volumes.snip'"
		COMPOSE_EMAIL_VOLUMES_SNIP="./custom/compose-email-volumes.snip"
	fi
	if [[ -f ./custom/docker-compose.yml.template ]]; then
		echo "--> Using custom 'docker-compose.yml.template'"
		COMPOSE_TEMPLATE="./custom/docker-compose.yml.template"
	fi
	if [[ -f ./custom/lemmy-email.snip ]]; then
		echo "--> Using custom 'lemmy-email.snip'"
		LEMMY_EMAIL_SNIP="./custom/lemmy-email.snip"
	fi
	if [[ -f ./custom/lemmy.hjson.template ]]; then
		echo "--> Using custom 'lemmy.hjson.template'"
		LEMMY_HJSON_TEMPLATE="./custom/lemmy.hjson.template"
	fi
fi

# Make sure the live dir exists
mkdir -p ./live

# Handle Backend source
if [[ "${BUILD_BACKEND}" == "1" ]]; then
	echo "Building Lemmy Backend from source"
	# Set the dockerfile path
	BACKEND_DOCKERFILE_PATH="docker/Dockerfile"

	# Set the build parameter for the compose file
	COMPOSE_LEMMY_IMAGE="build:\n      context: ./lemmy\n      dockerfile: ./${BACKEND_DOCKERFILE_PATH}"

	# Download source if it's not already downloaded
	# Initially check out whatever the latest tag is
	if [[ ! -d "./live/lemmy" ]]; then
		echo "Downloading Lemmy Backend source... (${LATEST_BACKEND:?})"
		git clone --recurse-submodules https://github.com/LemmyNet/lemmy ./live/lemmy
		(
			set -e
			cd ./live/lemmy
			git checkout ${LATEST_BACKEND:?}
		)

	fi

	# Skip checkout if REBUILD_SOURCE=1
	if [[ "${REBUILD_SOURCE}" == "1" ]]; then
		echo "WARNING: --rebuild was specified; not updating Lemmy Backend source files, building as-is"
	else
		echo "Checking out Lemmy Backend ${LATEST_BACKEND:?}..."
		(
			set -e
			cd ./live/lemmy
			git reset --hard
			git clean -fdx
			git checkout main
			git pull
			git checkout ${LATEST_BACKEND:?}
		)
	fi
fi

# Handle Frontend source
if [[ "${BUILD_FRONTEND}" == "1" ]]; then
	echo "Building Lemmy Backend from source (due to user-specified git: prefix)"
	# Set the dockerfile path
	FRONTEND_DOCKERFILE_PATH="docker/Dockerfile"

	# Set the build parameter for the compose file
	COMPOSE_LEMMY_UI_IMAGE="build:\n      context: ./lemmy-ui\n      dockerfile: ./${FRONTEND_DOCKERFILE_PATH}"

	# Download source if it's not already downloaded
	if [[ ! -d "./live/lemmy-ui" ]]; then
		echo "Downloading Lemmy Frontend source... (${LATEST_FRONTEND:?})"
		git clone --recurse-submodules https://github.com/LemmyNet/lemmy-ui ./live/lemmy-ui
		(
			set -e
			cd ./live/lemmy
			git checkout ${LATEST_FRONTEND:?}
		)
	fi

	# Skip checkout if REBUILD_SOURCE=1
	if [[ "${REBUILD_SOURCE}" == "1" ]]; then
		echo "WARNING: --rebuild was specified; not updating Lemmy Frontend source files, building as-is"
	else
		echo "Checking out Lemmy Frontend ${LATEST_BACKEND:?}..."
		(
			set -e
			cd ./live/lemmy-ui
			git reset --hard
			git clean -fdx
			git checkout main
			git pull
			git checkout ${LATEST_BACKEND:?}
		)
	fi
fi

echo

# Determine the images to use
# Try to use my images first, then the official ones
LEMMY_IMAGE_TAG="ghcr.io/ubergeek77/lemmy:${LATEST_BACKEND:?}"
if [[ -z "${COMPOSE_LEMMY_IMAGE}" ]]; then
	echo "Finding the best available Backend image, please wait..."
	if ! check_image_arch ${LEMMY_IMAGE_TAG:?}; then
		echo "! ${LEMMY_IMAGE_TAG} is not available for ${DOCKER_ARCH}"
		LEMMY_IMAGE_TAG="dessalines/lemmy:${LATEST_BACKEND:?}"
		echo "! Checking backup image at ${LEMMY_IMAGE_TAG}..."
		if ! check_image_arch ${LEMMY_IMAGE_TAG:?}; then
			echo >&2 "ERROR: A Lemmy Backend image for your architecture is not available (${DOCKER_ARCH})"
			echo >&2 "If you are confident that this image exists for '${DOCKER_ARCH}', please report this as an issue: "
			echo >&2 "    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issue"
			exit 1
		fi
	fi
	echo "--> Using Backend Image: ${LEMMY_IMAGE_TAG}"
	COMPOSE_LEMMY_IMAGE="image: ${LEMMY_IMAGE_TAG}"
	echo
fi

LEMMY_UI_IMAGE_TAG="ghcr.io/ubergeek77/lemmy-ui:${LATEST_FRONTEND:?}"
if [[ -z "${COMPOSE_LEMMY_UI_IMAGE}" ]]; then
	echo "Finding the best available Frontend image, please wait..."
	if ! check_image_arch ${LEMMY_UI_IMAGE_TAG:?}; then
		echo "! ${LEMMY_UI_IMAGE_TAG} is not available for ${DOCKER_ARCH}"
		LEMMY_UI_IMAGE_TAG="dessalines/lemmy-ui:${LATEST_FRONTEND:?}"
		echo "! Checking backup image at ${LEMMY_UI_IMAGE_TAG}..."
		if ! check_image_arch ${LEMMY_UI_IMAGE_TAG:?}; then
			echo >&2 "ERROR: A Lemmy Frontend image for your architecture is not available (${DOCKER_ARCH})"
			echo >&2 "If you are confident that this image exists for '${DOCKER_ARCH}', please report this as an issue: "
			echo >&2 "    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issue"
			exit 1
		fi
	fi
	echo "--> Using Frontend Image: ${LEMMY_UI_IMAGE_TAG}"
	COMPOSE_LEMMY_UI_IMAGE="image: ${LEMMY_UI_IMAGE_TAG}"
	echo
fi

# Caddy is reliable, I don't need to check it
COMPOSE_CADDY_IMAGE="image: caddy:latest"

# Generate all the env files, make a Caddy directory since we'll need it
mkdir -p ./live/caddy
if [[ ! -f "./live/pictrs.env" ]]; then
	echo "PICTRS__API_KEY=$(random_string)" >./live/pictrs.env
fi
if [[ ! -f "./live/postgres.env" ]]; then
	echo "POSTGRES_PASSWORD=$(random_string)" >./live/postgres.env
fi
if [[ ! -f "./live/lemmy.env" ]]; then
	echo "SETUP_ADMIN_PASS=$(random_string)" >./live/lemmy.env
fi
echo "LEMMY_HOSTNAME=${LEMMY_HOSTNAME}" >./live/caddy.env
echo "POSTFIX_myhostname=$LEMMY_HOSTNAME" >./live/postfix.env

# Source all the env files
source ./live/pictrs.env
source ./live/postgres.env
source ./live/caddy.env
source ./live/postfix.env
source ./live/lemmy.env

# Generate the Caddyfile
# Use the non-http config if configured
# Use Cloudflare snip if Cloudflare token is present
# We will need to build Caddy if Cloudflare is needed, so copy that to the live directory as well
# Otherwise, use the default config
if [[ "${CADDY_DISABLE_TLS}" == "true" ]] || [[ "${CADDY_DISABLE_TLS}" == "1" ]]; then
	sed -e 's|{$LEMMY_HOSTNAME}|http://{$LEMMY_HOSTNAME}|g' ${CADDYFILE_TEMPLATE:?} >./live/caddy/Caddyfile
elif [[ -n "${CF_API_TOKEN}" ]]; then
	cat ${CLOUDFLARE_SNIP:?} >./live/caddy/Caddyfile
	cat ${CADDY_DOCKERFILE_TEMPLATE:?} >./live/caddy/Dockerfile
	echo "CF_API_TOKEN=${CF_API_TOKEN}" >>./live/caddy.env
	sed -e '/import caddy-common/a\\timport cloudflare_https' ${CADDYFILE_TEMPLATE:?} >>./live/caddy/Caddyfile
	COMPOSE_CADDY_IMAGE="build: ./caddy"
else
	cat ${CADDYFILE_TEMPLATE:?} >./live/caddy/Caddyfile
fi

# Generate docker-compose.yml
sed -e "s|{{COMPOSE_CADDY_IMAGE}}|${COMPOSE_CADDY_IMAGE:?}|g" \
	-e "s|{{COMPOSE_LEMMY_IMAGE}}|${COMPOSE_LEMMY_IMAGE:?}|g" \
	-e "s|{{COMPOSE_LEMMY_UI_IMAGE}}|${COMPOSE_LEMMY_UI_IMAGE:?}|g" \
	-e "s|{{CADDY_HTTP_PORT}}|${CADDY_HTTP_PORT:?}|g" \
	-e "s|{{CADDY_HTTPS_PORT}}|${CADDY_HTTPS_PORT:?}|g" \
	${COMPOSE_TEMPLATE:?} >./live/docker-compose.yml

# If ENABLE_POSTFIX is enabled, add the postfix services to docker-compose.yml
# Also override ENABLE_EMAIL to true
if [[ "${ENABLE_POSTFIX}" == "1" ]] || [[ "${ENABLE_POSTFIX}" == "true" ]]; then
	ENABLE_EMAIL="true"
	sed -i -e "/{{EMAIL_SERVICE}}/r ${COMPOSE_EMAIL_SNIP:?}" ./live/docker-compose.yml
	sed -i -e "/{{EMAIL_VOLUMES}}/r ${COMPOSE_EMAIL_VOLUMES_SNIP:?}" ./live/docker-compose.yml
fi

# Delete the email templates if they exist
sed -i '/{{EMAIL_SERVICE}}/d' ./live/docker-compose.yml
sed -i '/{{EMAIL_VOLUMES}}/d' ./live/docker-compose.yml

# Add or delete the custom env/config sections, and copy the config files
install_custom_env

# Generate initial lemmy.hjson
sed -e "s|{{LEMMY_HOSTNAME}}|${LEMMY_HOSTNAME:?}|g" \
	-e "s|{{PICTRS__API_KEY}}|${PICTRS__API_KEY:?}|g" \
	-e "s|{{POSTGRES_PASSWORD}}|${POSTGRES_PASSWORD:?}|g" \
	-e "s|{{POSTGRES_POOL_SIZE}}|${POSTGRES_POOL_SIZE:?}|g" \
	-e "s|{{SETUP_ADMIN_PASS}}|${SETUP_ADMIN_PASS:?}|g" \
	-e "s|{{SETUP_ADMIN_USER}}|${SETUP_ADMIN_USER:?}|g" \
	-e "s|{{SETUP_SITE_NAME}}|${SETUP_SITE_NAME:?}|g" \
	-e "s|{{LEMMY_TLS_ENABLED}}|${LEMMY_TLS_ENABLED:?}|g" ${LEMMY_HJSON_TEMPLATE:?} >./live/lemmy.hjson

# If ENABLE_EMAIL is true, add the email block to the lemmy config
if [[ "${ENABLE_EMAIL}" == "1" ]] || [[ "${ENABLE_EMAIL}" == "true" ]]; then
	sed -i -e "/{{EMAIL_BLOCK}}/r ${LEMMY_EMAIL_SNIP:?}" ./live/lemmy.hjson

	sed -i -e "s|{{SMTP_SERVER}}|${SMTP_SERVER}|g" \
		-e "s|{{SMTP_PORT}}|${SMTP_PORT}|g" \
		-e "s|{{SMTP_NOREPLY_DISPLAY}}|${SMTP_NOREPLY_DISPLAY}|g" \
		-e "s|{{SMTP_TLS_TYPE}}|${SMTP_TLS_TYPE}|g" \
		-e "s|{{SMTP_LOGIN}}|${SMTP_LOGIN}|g" \
		-e "s|{{SMTP_PASSWORD}}|${SMTP_PASSWORD}|g" \
		-e "s|{{SMTP_NOREPLY_FROM}}|${SMTP_NOREPLY_FROM}|g" ./live/lemmy.hjson
fi

# Delete the email template if it exists
sed -i '/{{EMAIL_BLOCK}}/d' ./live/lemmy.hjson

# Run the user's pre-deploy script if it exists
# Run in a subshell so there's no environment/directory weirdness
if [[ -x ./custom/pre-deploy.sh ]]; then
	echo "--> Running custom pre-deploy script"
	(./custom/pre-deploy.sh)
fi

# Set up the new deployment
# Only run down if we can assume the user has a deployment already
(
	cd ./live
	$COMPOSE_CMD -p "lemmy-easy-deploy" pull
	$COMPOSE_CMD -p "lemmy-easy-deploy" build
	if [[ "${HAS_VOLUME}" == "1" ]]; then
		$COMPOSE_CMD -p "lemmy-easy-deploy" down || true
	fi
	$COMPOSE_CMD -p "lemmy-easy-deploy" up -d || true
)

# Run the user's post-deploy script if it exists
# Run in a subshell so there's no environment/directory weirdness
if [[ -x ./custom/post-deploy.sh ]]; then
	echo "--> Running custom post-deploy script"
	(./custom/post-deploy.sh)
fi

# Do health checks
# Give it 2 seconds to start up
echo ""
echo "Checking deployment status..."
sleep 2

# Services every deployment should have
declare -a health_checks=("proxy" "lemmy" "lemmy-ui" "pictrs" "postgres")

# Add postfix if the user configured that
if [[ "${ENABLE_POSTFIX}" == "true" ]] || [[ "${ENABLE_POSTFIX}" == "1" ]]; then
	health_checks+=("postfix")
fi

for service in "${health_checks[@]}"; do
	printf "Checking ${service}... "
	SERVICE_STATE="$(get_service_status $service)"
	if [[ "${SERVICE_STATE}" != "running" ]]; then
		# Give it a little bit...
		printf "${SERVICE_STATE} ... "
		sleep 5
		SERVICE_STATE="$(get_service_status $service)"
		if [[ "${SERVICE_STATE}" != "running" ]]; then
			echo "FAILED"
			echo ""
			echo >&2 "ERROR: Service $service unhealthy. Deployment failed."
			echo >&2 "Dumping logs... "
			LOG_FILENAME="failure-$(date +%s).log"
			$COMPOSE_CMD -p "lemmy-easy-deploy" logs >./${LOG_FILENAME:?}
			echo >&2 ""
			echo >&2 "Logs dumped to: ./${LOG_FILENAME:?}"
			echo >&2 "(DO NOT POST THESE LOGS PUBLICLY, THEY MAY CONTAIN SENSITIVE INFORMATION)"
			echo >&2 ""
			echo >&2 "Please check these logs for potential easy fixes before reporting an issue!"
			echo >&2 ""
			echo >&2 "Shutting down failed deployment..."
			$COMPOSE_CMD -p "lemmy-easy-deploy" down || true
			exit 1
		else
			echo "OK!"
		fi
	else
		echo "OK!"
	fi
	sleep 1
done

# Write version file
if [[ "${REBUILD_SOURCE}" == "1" ]]; then
	if [[ "${BUILD_BACKEND}" == "1" ]]; then
		LATEST_BACKEND="git"
	fi
	if [[ "${BUILD_FRONTEND}" == "1" ]]; then
		LATEST_FRONTEND="git"
	fi
fi

VERSION_STRING="${LATEST_BACKEND:?};${LATEST_FRONTEND:?}"

echo ${VERSION_STRING:?} >./live/version

echo
echo "Deploy complete!"
echo "   BE: ${LATEST_BACKEND}"
echo "   FE: ${LATEST_FRONTEND}"
echo ""
echo "--------------------------------------------------------------------------------------"
echo "NOTE: Please do not run from the ./live folder directly, or you may cause issues!"
echo ""
echo "To shut down your deployment, run:"
echo "    ./deploy.sh --shutdown"
echo ""
echo "To start your deployment back up, run"
echo "    ./deploy.sh"
echo ""
echo "If you must manage your deployment manually, it is critical to supply the stack name:"
echo "    $COMPOSE_CMD -p \"lemmy-easy-deploy\" [up/down/etc]"
echo ""
echo "--------------------------------------------------------------------------------------"

if [[ "${HAS_VOLUME}" == "0" ]]; then
	echo "Lemmy admin credentials:"
	cat ./live/lemmy.hjson | grep -e "admin_.*:"
	echo "--------------------------------------------------------------------------------------"
fi
