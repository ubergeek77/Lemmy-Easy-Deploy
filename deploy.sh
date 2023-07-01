#!/bin/bash

LED_CURRENT_VERSION="1.2.2"

# Trap exits

# cd to the directory the script is in
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd $SCRIPT_DIR

load_env() {
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

diag_info() {
	set +e
	load_env
	echo ""
	echo "==== Docker Information ===="
	detect_runtime
	echo "==== System Information ===="
	echo "KERNEL: $(uname -r) ($(uname -m))"
	echo "SHELL: $SHELL"
	if [[ ! -f "/etc/os-release" ]]; then
		echo "*** /etc/os-release not found ***"
	else
		cat /etc/os-release | grep --color=never NAME
	fi
	echo "MEMORY: $(free -h)"
	echo ""
	echo "==== Lemmy-Easy-Deploy Information ===="
	echo "Version: $LED_CURRENT_VERSION"
	echo ""
	docker ps --filter "name=lemmy-easy-deploy" --format "table {{.Image}}\t{{.RunningFor}}\t{{.Status}}"
	echo ""
	echo "Integrity:"
	echo "    $(sha256sum $0)"
	for f in ./templates/*; do
		echo "    $(sha256sum $f)"
	done
	echo ""
	echo "==== Settings ===="
	if [[ ! -f "./config.env" ]]; then
		echo "*** config.env not found ***"
	else
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
	if [[ ! -d "./live" ]]; then
		echo "*** No files generated ***"
	else
		echo "Deploy Version: $(cat ./live/version)"
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
	DOCKER_MAJOR="$(echo ${DOCKER_VERSION} | grep -oP "(?<=version )[^.]*")"
	COMPOSE_VERSION="$($COMPOSE_CMD version | head -n 1)"
	COMPOSE_MAJOR="$(echo ${COMPOSE_VERSION} | grep -oP "(?<=version )[^.]*")"

	echo "Detected runtime: $RUNTIME_CMD (${DOCKER_VERSION})"
	echo "Detected compose: $COMPOSE_CMD (${COMPOSE_VERSION})"

	RUNTIME_STATE="ERROR"
	if docker run --rm -v "$(pwd):/host:ro" hello-world >/dev/null 2>&1; then
		RUNTIME_STATE="OK"
	fi
	echo "   Runtime state: $RUNTIME_STATE"
	echo ""

	# Warn if using an unsupported version
	if ((DOCKER_MAJOR < 24)) || ((COMPOSE_MAJOR < 1)); then
		echo "-----------------------------------------------------------------------"
		echo "WARNING: Your version of Docker is outdated and unsupported."
		echo ""
		echo "The deployment will likely work regardless, but if you run into issues,"
		echo "please install the official version of Docker before filing an issue:"
		echo "    https://docs.docker.com/engine/install/"
		echo ""
		echo "This warning is not fatal. The script will now continue."
		echo ""
		echo "-----------------------------------------------------------------------"
	fi

}

display_help() {
	echo "Usage:"
	echo "  $0 [options]"
	echo ""
	echo "Run with no options to check for Lemmy updates and deploy them"
	echo ""
	echo "Options:"
	echo "  -s|--shutdown          Shut down a running Lemmy-Easy-Deploy deployment (does not delete data)"
	echo "  -l|--lemmy-tag <tag>   Install a specific version of the Lemmy Backend"
	echo "  -w|--webui-tag <tag>   Install a specific version of the Lemmy WebUI (will use value from --lemmy-tag if missing)"
	echo "  -f|--force-deploy      Skip the update checker and force (re)deploy the latest/specified version"
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
		echo ""
		echo "Update found!"
		echo "    ${LED_CURRENT_VERSION} --> ${LED_UPDATE_CHECK}"
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

	echo "--> Updating Lemmy-Easy-Deploy..."
	echo "-----------------------------------------------------------"
	if ! git checkout main; then
		print_update_error
		exit 1
	fi
	if ! git pull; then
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
	ratelimit_error='"message":"API rate limit exceeded for'
	RESPONSE="$(curl -s https://api.github.com/repos/$1/releases/latest)"
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

	# If no result, check the latest tag that doesn't contain the words beta or rc
	if [[ -z "${RESULT}" ]]; then
		RESPONSE="$(curl -s https://api.github.com/repos/$1/git/refs/tags)"
		while IFS= read -r line; do
			if [[ "${line,,}" != *beta* && "${line,,}" != *rc* ]]; then
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
	local prompt="${1} [Y/n] "

	# Always answer yes if the user specified -y
	if [[ "${ANSWER_YES}" == "1" ]]; then
		echo "$prompt Y"
		return 0
	fi

	while true; do
		read -rp "$prompt" answer

		case "${answer,,}" in
		y | yes | "")
			return 0
			break
			;;
		n | no)
			return 1
			break
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
		print_version
		exit 0
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

# Check for LED updates
LED_UPDATE_CHECK="$(latest_github_tag ubergeek77/Lemmy-Easy-Deploy)"

# Check if this version is newer
if [[ "$(compare_versions ${LED_CURRENT_VERSION} ${LED_UPDATE_CHECK})" == "1" ]]; then
	echo
	echo "================================================================"
	echo "|   A new Lemmy-Easy-Deploy update is available!"
	echo "|       ${LED_CURRENT_VERSION} --> ${LED_UPDATE_CHECK}"
	echo "================================================================"
	echo
	# Exclude update from unattended yes answers
	USER_ANSWER_YES="${ANSWER_YES}"
	ANSWER_YES=0
	if ask_user "Would you like to install the update?"; then
		self_update
		exit 0
	fi
	ANSWER_YES="${USER_ANSWER_YES}"
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
	echo >&2 "ERROR: Docker runtime not healthy."
	echo >&2 "Something is wrong with your Docker installation."
	echo >&2 "Please ensure you can run the following command on your own without errors:"
	echo >&2 "    docker run --rm -v "\$\(pwd\):/host:ro" hello-world"
	echo >&2 ""
	echo >&2 "If you see any errors while running that command, please Google the error messages"
	echo >&2 "to see if any of the solutions work for you. Once Docker is functional on your system,"
	echo >&2 "you can try running Lemmy-Easy-Deploy again."
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
	echo >&2 "ERROR: You did not set your hostname in hostname.env! Do it like this:"
	echo >&2 "LEMMY_HOSTNAME=example.com"
	exit 1
fi
if [[ $LEMMY_HOSTNAME =~ ^https?: ]]; then
	echo >&2 "ERROR: Don't put http/https in hostname.env! Do it like this:"
	echo >&2 "LEMMY_HOSTNAME=example.com"
	exit 1
fi

# Check for config oddities
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

# Determine Backend update version
# Allow the user to override the version to update to

LATEST_BACKEND="${BACKEND_TAG_OVERRIDE}"
if [[ -z "${LATEST_BACKEND}" ]]; then
	LATEST_BACKEND="$(latest_github_tag LemmyNet/lemmy)"
fi
echo " Current Backend Version: ${CURRENT_BACKEND:?}"
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
			echo "-----------------------------------------------------------------------------------------------------------"
			echo >&2 "ERROR: Unable to determine Backend upgrade path. One of the below versions is not in 0.0.0 format:"
			echo >&2 "   Installed Backend: ${CURRENT_BACKEND}"
			echo >&2 "      Target Backend: ${LATEST_BACKEND}"
			echo >&2 ""
			echo >&2 "Did you install a commit/tag/rc version manually? If so, use the following command to manually upgrade:"
			echo >&2 "$0 -l <some-tag> -f"
			echo >&2 ""
			echo >&2 "This will get your deployment back on an \"update track\" and allow for auto updates again."
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
echo " Current Frontend Version: ${CURRENT_FRONTEND:?}"
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
			echo >&2 "ERROR: Unable to determine Frontend upgrade path. One of the below versions is not in 0.0.0 format:"
			echo "-----------------------------------------------------------------------------------------------------------"
			echo >&2 "   Installed Frontend: ${CURRENT_FRONTEND}"
			echo >&2 "      Target Frontend: ${LATEST_FRONTEND}"
			echo >&2 ""
			echo >&2 "Did you install a commit/tag/rc version manually? If so, use the following command to manually upgrade:"
			echo >&2 "$0 -w <some-tag> -f"
			echo >&2 ""
			echo >&2 "This will get your deployment back on an \"update track\" and allow for auto updates again."
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
	if [[ "${BACKEND_OUTDATED}" == "1" ]]; then
		echo "A Backend update is available!"
		echo "   BE: ${CURRENT_BACKEND} --> ${LATEST_BACKEND}"
		echo
	fi

	if [[ "${FRONTEND_OUTDATED}" == "1" ]]; then
		echo "A Frontend update is available!"
		echo "   FE: ${CURRENT_FRONTEND} --> ${LATEST_FRONTEND}"
		echo
	fi
fi

# Ask the user if they want to update
if [[ "${BACKEND_OUTDATED}" == "1" ]] || [[ "${FRONTEND_OUTDATED}" == "1" ]]; then
	# Print scary warning if this is a backend update and data exists
	if docker volume inspect lemmy-easy-deploy_postgres_data >/dev/null 2>&1 && [[ "${BACKEND_OUTDATED}" == "1" ]]; then
		echo "--------------------------------------------------------------------|"
		echo "|  !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!! WARNING !!!  |"
		echo "|                                                                   |"
		echo "| Updates to the Lemmy Backend perform a database migration!        |"
		echo "|                                                                   |"
		echo "| This process is **generally safe and does not risk data loss.**   |"
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
	if ! ask_user "Would you like to deploy this update?"; then
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
	sed -e 's|{$LEMMY_HOSTNAME}|http://{$LEMMY_HOSTNAME}|g' ./templates/Caddyfile.template >./live/caddy/Caddyfile
elif [[ -n "${CF_API_TOKEN}" ]]; then
	cat ./templates/cloudflare.snip >./live/caddy/Caddyfile
	cat ./templates/Caddy-Dockerfile.template >./live/caddy/Dockerfile
	echo "CF_API_TOKEN=${CF_API_TOKEN}" >>./live/caddy.env
	sed -e '/import caddy-common/a\\timport cloudflare_https' ./templates/Caddyfile.template >>./live/caddy/Caddyfile
	COMPOSE_CADDY_IMAGE="build: ./caddy"
else
	cat ./templates/Caddyfile.template >./live/caddy/Caddyfile
fi

# Generate docker-compose.yml
sed -e "s|{{COMPOSE_CADDY_IMAGE}}|${COMPOSE_CADDY_IMAGE:?}|g" \
	-e "s|{{COMPOSE_LEMMY_IMAGE}}|${COMPOSE_LEMMY_IMAGE:?}|g" \
	-e "s|{{COMPOSE_LEMMY_UI_IMAGE}}|${COMPOSE_LEMMY_UI_IMAGE:?}|g" \
	-e "s|{{CADDY_HTTP_PORT}}|${CADDY_HTTP_PORT:?}|g" \
	-e "s|{{CADDY_HTTPS_PORT}}|${CADDY_HTTPS_PORT:?}|g" \
	./templates/docker-compose.yml.template >./live/docker-compose.yml

# If ENABLE_POSTFIX is enabled, add the postfix services to docker-compose.yml
# Also override ENABLE_EMAIL to true
if [[ "${ENABLE_POSTFIX}" == "1" ]] || [[ "${ENABLE_POSTFIX}" == "true" ]]; then
	ENABLE_EMAIL="true"
	sed -i -e '/{{EMAIL_SERVICE}}/r ./templates/compose-email.snip' ./live/docker-compose.yml
	sed -i -e '/{{EMAIL_VOLUMES}}/r ./templates/compose-email-volumes.snip' ./live/docker-compose.yml
fi

# Delete the email templates if they exist
sed -i '/{{EMAIL_SERVICE}}/d' ./live/docker-compose.yml
sed -i '/{{EMAIL_VOLUMES}}/d' ./live/docker-compose.yml

# Generate initial lemmy.hjson
sed -e "s|{{LEMMY_HOSTNAME}}|${LEMMY_HOSTNAME:?}|g" \
	-e "s|{{PICTRS__API_KEY}}|${PICTRS__API_KEY:?}|g" \
	-e "s|{{POSTGRES_PASSWORD}}|${POSTGRES_PASSWORD:?}|g" \
	-e "s|{{POSTGRES_POOL_SIZE}}|${POSTGRES_POOL_SIZE:?}|g" \
	-e "s|{{SETUP_ADMIN_PASS}}|${SETUP_ADMIN_PASS:?}|g" \
	-e "s|{{SETUP_ADMIN_USER}}|${SETUP_ADMIN_USER:?}|g" \
	-e "s|{{SETUP_SITE_NAME}}|${SETUP_SITE_NAME:?}|g" \
	-e "s|{{LEMMY_TLS_ENABLED}}|${LEMMY_TLS_ENABLED:?}|g" ./templates/lemmy.hjson.template >./live/lemmy.hjson

# If ENABLE_EMAIL is true, add the email block to the lemmy config
if [[ "${ENABLE_EMAIL}" == "1" ]] || [[ "${ENABLE_EMAIL}" == "true" ]]; then
	sed -i -e '/{{EMAIL_BLOCK}}/r ./templates/lemmy-email.snip' ./live/lemmy.hjson

	sed -i -e "s|{{SMTP_SERVER}}|${SMTP_SERVER}|g" \
		-e "s|{{SMTP_PORT}}|${SMTP_PORT}|g" \
		-e "s|{{LEMMY_NOREPLY_DISPLAY}}|${LEMMY_NOREPLY_DISPLAY}|g" \
		-e "s|{{SMTP_TLS_TYPE}}|${SMTP_TLS_TYPE}|g" \
		-e "s|{{SMTP_LOGIN}}|${SMTP_LOGIN}|g" \
		-e "s|{{SMTP_PASSWORD}}|${SMTP_PASSWORD}|g" \
		-e "s|{{SMTP_NOREPLY_FROM}}|${SMTP_NOREPLY_FROM}|g" ./live/lemmy.hjson
fi

# Delete the email template if it exists
sed -i '/{{EMAIL_BLOCK}}/d' ./live/lemmy.hjson

# Set up the new deployment
(
	cd ./live
	$COMPOSE_CMD -p "lemmy-easy-deploy" pull
	$COMPOSE_CMD -p "lemmy-easy-deploy" build
	$COMPOSE_CMD -p "lemmy-easy-deploy" down || true
	$COMPOSE_CMD -p "lemmy-easy-deploy" up -d || true
)

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
echo

if [[ "${CURRENT_BACKEND}" == "0.0.0" ]]; then
	echo "============================================="
	echo "Lemmy admin credentials:"
	cat ./live/lemmy.hjson | grep -e "admin_.*:"
	echo "============================================="
fi
