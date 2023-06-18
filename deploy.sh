#!/bin/bash

# cd to the directory the script is in
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd $SCRIPT_DIR

random_string() {
	length=32
	string=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "$length" | head -n 1)
	echo "$string"
}

display_help() {
	echo "Usage:"
	echo "  $0 [-u|--update-version <version>] [-f|--force-deploy] [-h|--help]"
	echo ""
	echo "Options:"
	echo "  -u|--update-version <version>   Override the update checker and update to <version> instead."
	echo "  -f|--force-deploy               Skip the update checker and force (re)deploy the latest/specified version."
	echo "  -h|--help                       Show this help message."
	exit 1
}

# Check for LED updates
LED_CURRENT_VERSION="1.0.1"
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

# Exit on error
set -e

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

echo
echo "Detected runtime: $($RUNTIME_CMD --version)"
echo "Detected compose: $($COMPOSE_CMD version)"
echo

# Yell at the user if they didn't follow instructions
if [[ ! -f "./config.env" ]]; then
	echo >&2 "ERROR: ./config.env not found! Did you copy the example config?"
	echo "    Try: cp ./config.env.example ./config.env"
	exit 1
fi

# Source the config file
source ./config.env

# Make sure nothing is missing
for config in "LEMMY_HOSTNAME" "BUILD_FROM_SOURCE" "SETUP_SITE_NAME" "CADDY_HTTP_PORT" "CADDY_HTTPS_PORT" "USE_EMAIL" "CADDY_DISABLE_TLS" "POSTGRES_POOL_SIZE" "TLS_ENABLED" "SETUP_ADMIN_USER" "LEMMY_NOREPLY_DISPLAY" "LEMMY_NOREPLY_FROM"; do
	if [ -z "${!config}" ]; then
		echo >&2 "ERROR: Missing config value for '$config'"
		echo >&2 "Please do not delete any config options from config.env."
		echo >&2 "See config.env.example for expected default values."
		exit 1
	fi
done

# Yell at the user if they didn't follow instructions, again
if [[ -z "$LEMMY_HOSTNAME" ]] || [[ "$LEMMY_HOSTNAME" == "example.com" ]]; then
	echo >&2 "ERROR: You did not set your hostname in hostname.env! Do it like this:"
	echo >&2 "LEMMY_HOSTNAME=example.com"
	exit 1
fi
if [[ $LEMMY_HOSTNAME == http* ]]; then
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
echo
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

# Define default strings for docker-compose.yml
COMPOSE_CADDY_IMAGE="image: caddy:latest"
COMPOSE_LEMMY_IMAGE="image: dessalines/lemmy:${LEMMY_VERSION:?}"
COMPOSE_LEMMY_UI_IMAGE="image: dessalines/lemmy-ui:${LEMMY_VERSION:?}"

# If the current system is not x86_64, we can't use the Docker Hub images
CURRENT_PLATFORM="$(uname -m)"
if [[ "${CURRENT_PLATFORM:?}" != "x86_64" ]]; then
	BUILD_FROM_SOURCE="true"
	echo
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo "WARN: Docker Hub does not have a Lemmy image that supports your platform ($CURRENT_PLATFORM)"
	echo "Lemmy-Easy-Deploy will now fall back to compiling Lemmy from source. This may take about 30 minutes!"
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo
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
		git checkout main
		git pull
		git checkout ${LEMMY_VERSION:?}
	) || {
		echo >&2 "ERROR: Failed to check out lemmy ${LEMMY_VERSION}"
		echo >&2 "If you manually specified a version, it may not exist. If you didn't, this might be a bug. Please report it:"
		echo >&2 "    https://github.com/ubergeek77/Lemmy-Easy-Deploy/issues"
		exit 1
	}

	COMPOSE_LEMMY_IMAGE="build:\n      context: ./lemmy\n      dockerfile: ./docker/prod/Dockerfile"
	COMPOSE_LEMMY_UI_IMAGE="build: ./lemmy-ui"
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
(
	cd ./live
	$COMPOSE_CMD -p "lemmy-easy-deploy" down || true
	$COMPOSE_CMD -p "lemmy-easy-deploy" up -d
)

# Write version file
echo ${LEMMY_VERSION:?} >./live/version

echo "Setup complete! Lemmy version ${LEMMY_VERSION:?} deployed!"
echo

if [[ "${CURRENT_VERSION}" == "0.0.0" ]]; then
	echo "============================================="
	echo "Lemmy admin credentials:"
	cat ./live/lemmy.hjson | grep -e "admin_.*:"
	echo "============================================="
fi
