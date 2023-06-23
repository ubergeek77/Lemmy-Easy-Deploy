#!/bin/bash

LED_CURRENT_VERSION="1.1.4"

# cd to the directory the script is in
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd $SCRIPT_DIR

load_env() {
	# Source the config file
	source ./config.env

	# Make sure nothing is missing
	LEMMY_HOSTNAME="${LEMMY_HOSTNAME:-example.com}"
	BUILD_FROM_SOURCE="${BUILD_FROM_SOURCE:-false}"
	SETUP_SITE_NAME="${SETUP_SITE_NAME:-Lemmy}"
	CADDY_HTTP_PORT="${CADDY_HTTP_PORT:-80}"
	CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT:-443}"
	USE_EMAIL="${USE_EMAIL:-false}"
	CADDY_DISABLE_TLS="${CADDY_DISABLE_TLS:-false}"
	POSTGRES_POOL_SIZE="${POSTGRES_POOL_SIZE:-5}"
	TLS_ENABLED="${TLS_ENABLED:-true}"
	SETUP_ADMIN_USER="${SETUP_ADMIN_USER:-lemmy}"
	LEMMY_NOREPLY_DISPLAY="${LEMMY_NOREPLY_DISPLAY:-Lemmy NoReply}"
	LEMMY_NOREPLY_FROM="${LEMMY_NOREPLY_FROM:-noreply}"
}

diag_info() {
	set +e
	echo ""
	echo "==== Docker Information ===="
	detect_runtime
	echo "==== System Information ===="
	echo "MEMORY: $(free -h)"
	echo ""
	echo "KERNEL: $(uname -r) ($(uname -m))"
	echo "SHELL: $SHELL"
	if [[ ! -f "/etc/os-release" ]]; then
		echo "*** /etc/os-release not found ***"
	else
		cat /etc/os-release
	fi
	echo ""
	echo "==== Lemmy Easy Deploy Information ===="
	echo "Version: $LED_CURRENT_VERSION"
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
		load_env
		echo "BUILD_FROM_SOURCE=$BUILD_FROM_SOURCE"
		echo "CADDY_HTTP_PORT=$CADDY_HTTP_PORT"
		echo "CADDY_HTTPS_PORT=$CADDY_HTTPS_PORT"
		echo "USE_EMAIL=$USE_EMAIL"
		echo "CADDY_DISABLE_TLS=$CADDY_DISABLE_TLS"
		echo "POSTGRES_POOL_SIZE=$POSTGRES_POOL_SIZE"
		echo "TLS_ENABLED=$TLS_ENABLED"
	fi
	echo ""
	echo "==== Generated Files ===="
	if [[ ! -d "./live" ]]; then
		echo "*** No files generated ***"
	else
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
		echo "WARN: podman will probably work, but I haven't tested it much. It's up to you to make sure all the permissions for podman are correct!"
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

	echo "Detected runtime: $RUNTIME_CMD ($($RUNTIME_CMD --version))"
	echo "Detected compose: $COMPOSE_CMD ($($COMPOSE_CMD version))"

	RUNTIME_STATE="ERROR"
	if docker run --rm -it -v "$(pwd):/host:ro" hello-world >/dev/null 2>&1; then
		RUNTIME_STATE="OK"
	fi
	echo "   Runtime state: $RUNTIME_STATE"
	echo ""
}

display_help() {
	echo "Usage:"
	echo "  $0 [-u|--update-version <version>] [-f|--force-deploy] [-d|--diag] [-h|--help]"
	echo ""
	echo "Options:"
	echo "  -u|--update-version <version>   Override the update checker and update to <version> instead."
	echo "  -f|--force-deploy               Skip the update checker and force (re)deploy the latest/specified version."
	echo "  -d|--diag                       Dump diagnostic information for issue reporting, then exit"
	echo "  -h|--help                       Show this help message."
	exit 1
}

# Check for LED updates
LED_UPDATE_CHECK="$(curl -s https://api.github.com/repos/ubergeek77/Lemmy-Easy-Deploy/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')"

# Check if this version is newer
IFS='.' read -ra fields <<<"$LED_CURRENT_VERSION"
_major=${fields[0]}
_minor=${fields[1]}
_micro=${fields[2]}
LED_CURRENT_VERSION_NUMERIC=$((_major * 10000 + _minor * 1000 + _micro))

IFS='.' read -ra fields <<<"$LED_UPDATE_CHECK"
_major=${fields[0]}
_minor=${fields[1]}
_micro=${fields[2]}
LED_UPDATE_CHECK_NUMERIC=$((_major * 10000 + _minor * 1000 + _micro))

if ((LED_CURRENT_VERSION_NUMERIC < LED_UPDATE_CHECK_NUMERIC)); then
	echo
	echo "================================================================"
	echo "|   A new Lemmy-Easy-Deploy update is available!"
	echo "|       ${LED_CURRENT_VERSION} --> ${LED_UPDATE_CHECK}"
	if [[ -d "./.git" ]]; then
		echo "|"
		echo "|   Please consider running 'git pull' to download the update!"
		echo "|   Alternatively:"
	fi
	echo "|"
	echo "|   You can visit the repo to download the update:"
	echo "|      https://github.com/ubergeek77/Lemmy-Easy-Deploy"
	echo "================================================================"
fi

# parse arguments
while (("$#")); do
	case "$1" in
	-u | --update-version)
		if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
			UPDATE_VERSION_OVERRIDE="$2"
			shift 2
		else
			echo "ERROR: Argument for $1 is missing" >&2
			exit 1
		fi
		;;
	-f | --force-deploy)
		FORCE_DEPLOY=1
		echo "WARN: Force deploying; this will regenerate configs and deploy again even if there were no updates"
		echo "Passwords will NOT be re-generated"
		shift
		;;
	-h | --help)
		display_help
		;;
	-d | --diag)
		diag_info
		exit 0
		;;
	-* | --*)
		echo "ERROR: Unsupported flag $1" >&2
		display_help
		exit 1
		;;
	*)
		echo "ERROR: Invalid argument $1" >&2
		display_help
		exit 1
		;;
	esac
done

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
	echo >&2 "    docker run --rm -it -v "\$\(pwd\):/host:ro" hello-world"
	echo >&2 ""
	echo >&2 "If you see any errors while running that command, please Google the error messages"
	echo >&2 "to see if any of the solutions work for you. Once Docker is functional on your system,"
	echo >&2 "you can try running Lemmy Easy Deploy again."
	echo >&2 ""
	exit 1
fi

# Exit on error
set -e

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

# Read the user's current version of Lemmy
if [[ -f "./live/version" ]]; then
	CURRENT_VERSION="$(cat ./live/version)"
else
	CURRENT_VERSION="0.0.0"
fi
echo " Current Lemmy version: ${CURRENT_VERSION:?}"

# If the user specified a version to update to, use that version
# Otherwise, detect the latest version from GitHub
if [[ -n "$UPDATE_VERSION_OVERRIDE" ]]; then
	LEMMY_VERSION="$UPDATE_VERSION_OVERRIDE"
	echo "Manual upgrade version: ${LEMMY_VERSION:?}"
else
	LEMMY_VERSION="$(curl -s https://api.github.com/repos/LemmyNet/lemmy/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')"
	echo "  Latest Lemmy version: ${LEMMY_VERSION:?}"
	echo

	# Pre-check the version strings
	if [[ ! $CURRENT_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! $LEMMY_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo >&2 "ERROR: Unable to determine Lemmy upgrade path. One of the below versions is not in 0.0.0 format:"
		echo >&2 "Installed version: $CURRENT_VERSION"
		echo >&2 "   Target version: $LEMMY_VERSION"
		echo >&2 ""
		echo >&2 "Did you install a commit/tag/rc version manually? If so, use the following command to manually upgrade:"
		echo >&2 "./$0 -u <some-version> -f"
		echo >&2 ""
		echo >&2 "If you did not do anything special with your installation, and are confused by this message, please report this:"
		echo >&2 "    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issues"
		exit 1
	fi

	# Check if this version is newer
	IFS='.' read -ra fields <<<"$CURRENT_VERSION"
	_major=${fields[0]}
	_minor=${fields[1]}
	_micro=${fields[2]}
	CURRENT_VERSION_NUMERIC=$((_major * 10000 + _minor * 1000 + _micro))

	IFS='.' read -ra fields <<<"$LEMMY_VERSION"
	_major=${fields[0]}
	_minor=${fields[1]}
	_micro=${fields[2]}
	LEMMY_VERSION_NUMERIC=$((_major * 10000 + _minor * 1000 + _micro))

	if [[ "${FORCE_DEPLOY}" == "1" ]] || ((CURRENT_VERSION_NUMERIC < LEMMY_VERSION_NUMERIC)); then
		echo "Update available!"
		echo
		echo "$CURRENT_VERSION --> $LEMMY_VERSION"
		echo
	else
		echo "No updates available."
		exit 0
	fi
fi

if [[ $LEMMY_VERSION == *"0.18"* ]]; then
	echo ""
	echo "UPGRADING TO 0.18.0 IS DISABLED DUE TO MULTIPLE SERVER-BREAKING ISSUES:"
	echo "  * https://github.com/LemmyNet/lemmy/issues/3296"
	echo "  * https://github.com/LemmyNet/lemmy-ui/issues/1530"
	echo ""
	echo "These are NOT Lemmy-Easy-Deploy issues, these are core Lemmy issues!"
	echo ""
	echo "For the safety of your data, Lemmy-Easy-Deploy will NOT upgrade your deployment to 0.18.x"
	echo ""
	echo "I will keep an eye on the Lemmy project and remove this block when upgrading is safe. In the meantime,"
	echo "you can try deploying 0.17.4 instead:"
	echo ""
	echo "./deploy.sh -u 0.17.4"
	echo ""
	echo "This script will now exit."
	echo ""
	exit 1
fi

# Define default strings for docker-compose.yml
COMPOSE_CADDY_IMAGE="image: caddy:latest"
COMPOSE_LEMMY_IMAGE="image: dessalines/lemmy:${LEMMY_VERSION:?}"
COMPOSE_LEMMY_UI_IMAGE="image: dessalines/lemmy-ui:${LEMMY_VERSION:?}"

# If the current system is not x86_64, we can't use the Docker Hub images
CURRENT_PLATFORM="$(uname -m)"

if [[ "${CURRENT_PLATFORM:?}" != "x86_64" ]]; then
	BUILD_FROM_SOURCE="true"
	echo
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo "WARN: Builds for your platform ($CURRENT_PLATFORM) are currently broken"
	echo "See this issue for more details: https://github.com/LemmyNet/lemmy/issues/3102"
	echo "In the optimistic case that you are trying to deploy 0.17.4 or below, Lemmy Easy Deploy will continue"
	echo "But otherwise, if you're trying to deploy 0.18.0, you will see some errors and the deploy will fail :("
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo
	echo "Continuing in 10 seconds..."
	sleep 10
fi

# Download the sources if we are doing a from-source build
mkdir -p ./live
if [[ "${BUILD_FROM_SOURCE}" == "true" ]] || [[ "${BUILD_FROM_SOURCE}" == "1" ]]; then
	echo "Source building enabled. Updating local Git repos..."

	# Download Lemmy source if it's not already downloaded
	if [[ ! -d "./live/lemmy" ]]; then
		echo "Downloading Lemmy source..."
		git clone --recurse-submodules https://github.com/LemmyNet/lemmy ./live/lemmy
	fi

	# Download Lemmy-UI source if it's not already downloaded
	if [[ ! -d "./live/lemmy-ui" ]]; then
		echo "Downloading Lemmy-UI source..."
		git clone --recurse-submodules https://github.com/LemmyNet/lemmy-ui ./live/lemmy-ui
	fi

	# Check out the right version of Lemmy and Lemmy UI
	echo "Checking out Lemmy ${LEMMY_VERSION:?}..."
	(
		set -e
		cd ./live/lemmy
		git reset --hard
		git clean -fdx
		git checkout main
		git pull
		git checkout ${LEMMY_VERSION:?}
	) || {
		echo >&2 "ERROR: Failed to check out lemmy ${LEMMY_VERSION}"
		echo >&2 "If you manually specified a version, it may not exist. If you didn't, this might be a bug. Please report it:"
		echo >&2 "    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issues"
		exit 1
	}

	(
		set -e
		cd ./live/lemmy-ui
		git reset --hard
		git clean -fdx
		git checkout main
		git pull
		git checkout ${LEMMY_VERSION:?}
	) || {
		echo >&2 "ERROR: Failed to check out lemmy ${LEMMY_VERSION}"
		echo >&2 "If you manually specified a version, it may not exist. If you didn't, this might be a bug. Please report it:"
		echo >&2 "    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issues"
		exit 1
	}

	# TEMPORARY 0.18 COMPATIBILITY FIXES
	# Search for docker/Dockerfile first (0.18), and if it doesn't exist.
	# fall back to docker/prod/Dockerfile (0.17.4)
	# If docker/Dockerfile exists, don't append .arm since they removed it
	# I have no idea if 0.18 even builds on ARM yet. Sorry to anyone if it doesn't!
	# I'll get a more formal fix out for any 0.18 issues once it releases and I have some time
	# What will likely end up happening is 0.17 support is removed. Not much sense running an old version anyway
	# Also determine if .arm should be appended to the Dockerfile path
	# I know this is terrible but I don't want to wake up to a bunch of issues and it's late T_T
	if [[ -f ./live/lemmy/docker/Dockerfile ]]; then
		ARM_SUFFIX=""
		LEMMY_DOCKERFILE_PATH="docker/Dockerfile"
	else
		ARM_SUFFIX=".arm"
		LEMMY_DOCKERFILE_PATH="docker/prod/Dockerfile"
	fi

	# If the current platform isn't ARM either, this platform is not supported
	if [[ "${CURRENT_PLATFORM:?}" != "x86_64" ]]; then
		if [[ "$CURRENT_PLATFORM" == arm* ]] || [[ "$CURRENT_PLATFORM" == "aarch64" ]]; then
			LEMMY_DOCKERFILE_PATH="${LEMMY_DOCKERFILE_PATH:?}${ARM_SUFFIX}"
		else
			echo >&2 "ERROR: Unknown architecture: $CURRENT_PLATFORM"
			echo >&2 "Unfortunately, Lemmy Easy Deploy does not support your architecture at this time :("
			exit 1
		fi
	fi

	COMPOSE_LEMMY_IMAGE="build:\n      context: ./lemmy\n      dockerfile: ./${LEMMY_DOCKERFILE_PATH}"
	COMPOSE_LEMMY_UI_IMAGE="build: ./lemmy-ui"

	# Make sure that Dockerfile actually exists
	if [[ ! -f "./live/lemmy/${LEMMY_DOCKERFILE_PATH}" ]]; then
		echo >&2 ""
		echo >&2 "ERROR: Unable to find Lemmy Dockerfile for building"
		echo >&2 "    No such file: ./live/lemmy/${LEMMY_DOCKERFILE_PATH}"
		echo >&2 ""
		echo >&2 "It is likely that Lemmy restructured their build files in a recent update."
		echo >&2 "If Lemmy Easy Deploy is already up to date, please report this so I can find the correct file path:"
		echo >&2 "    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issues"
		exit 1
	fi
fi

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

# Generate lemmy.hjson
sed -e "s|{{LEMMY_HOSTNAME}}|${LEMMY_HOSTNAME:?}|g" \
	-e "s|{{PICTRS__API_KEY}}|${PICTRS__API_KEY:?}|g" \
	-e "s|{{POSTGRES_PASSWORD}}|${POSTGRES_PASSWORD:?}|g" \
	-e "s|{{POSTGRES_POOL_SIZE}}|${POSTGRES_POOL_SIZE:?}|g" \
	-e "s|{{SETUP_ADMIN_PASS}}|${SETUP_ADMIN_PASS:?}|g" \
	-e "s|{{SETUP_ADMIN_USER}}|${SETUP_ADMIN_USER:?}|g" \
	-e "s|{{SETUP_SITE_NAME}}|${SETUP_SITE_NAME:?}|g" \
	-e "s|{{TLS_ENABLED}}|${TLS_ENABLED:?}|g" ./templates/lemmy.hjson.template >./live/lemmy.hjson

# Generate docker-compose.yml
sed -e "s|{{COMPOSE_CADDY_IMAGE}}|${COMPOSE_CADDY_IMAGE:?}|g" \
	-e "s|{{COMPOSE_LEMMY_IMAGE}}|${COMPOSE_LEMMY_IMAGE:?}|g" \
	-e "s|{{COMPOSE_LEMMY_UI_IMAGE}}|${COMPOSE_LEMMY_UI_IMAGE:?}|g" \
	-e "s|{{CADDY_HTTP_PORT}}|${CADDY_HTTP_PORT:?}|g" \
	-e "s|{{CADDY_HTTPS_PORT}}|${CADDY_HTTPS_PORT:?}|g" \
	./templates/docker-compose.yml.template >./live/docker-compose.yml

if [[ "${USE_EMAIL}" == "true" ]] || [[ "${USE_EMAIL}" == "1" ]]; then
	sed -i -e '/{{EMAIL_BLOCK}}/r ./templates/lemmy-email.snip' ./live/lemmy.hjson
	sed -i -e '/{{EMAIL_SERVICE}}/r ./templates/compose-email.snip' ./live/docker-compose.yml
	sed -i -e '/{{EMAIL_VOLUMES}}/r ./templates/compose-email-volumes.snip' ./live/docker-compose.yml
fi
sed -i '/{{EMAIL_BLOCK}}/d' ./live/lemmy.hjson
sed -i '/{{EMAIL_SERVICE}}/d' ./live/docker-compose.yml
sed -i '/{{EMAIL_VOLUMES}}/d' ./live/docker-compose.yml

sed -i -e "s|{{LEMMY_HOSTNAME}}|${LEMMY_HOSTNAME:?}|g" \
	-e "s|{{LEMMY_NOREPLY_DISPLAY}}|${LEMMY_NOREPLY_DISPLAY:?}|g" \
	-e "s|{{LEMMY_NOREPLY_FROM}}|${LEMMY_NOREPLY_FROM:?}|g" ./live/lemmy.hjson

# Set up the new deployment
# Pull and build before running down/up to reduce downtime
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
if [[ "${USE_EMAIL}" == "true" ]] || [[ "${USE_EMAIL}" == "1" ]]; then
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
echo ${LEMMY_VERSION:?} >./live/version

echo
echo "Setup complete! Lemmy version ${LEMMY_VERSION:?} deployed!"
echo

if [[ "${CURRENT_VERSION}" == "0.0.0" ]]; then
	echo "============================================="
	echo "Lemmy admin credentials:"
	cat ./live/lemmy.hjson | grep -e "admin_.*:"
	echo "============================================="
fi
