#!/bin/sh
set -e

DNS=localhost
SYSTEM_TZ=UTC

DEFAULT_CHANNEL_VALUE="stable"
if [ -z "$CHANNEL" ]; then
	CHANNEL=$DEFAULT_CHANNEL_VALUE
fi

DEFAULT_DOWNLOAD_URL="https://download.docker.com"
if [ -z "$DOWNLOAD_URL" ]; then
	DOWNLOAD_URL=$DEFAULT_DOWNLOAD_URL
fi

DEFAULT_REPO_FILE="docker-ce.repo"
if [ -z "$REPO_FILE" ]; then
	REPO_FILE="$DEFAULT_REPO_FILE"
fi

ROOT_DIR_2SMART=$(pwd)
CURRENT_DIR_NAME=${PWD##*/}

# SMART_POST_INSTALL_IMAGE="$DOCKER_2SMART_REGISTRY/2smart/standalone/utils/post-installation-service:release"

SMART_CONFIG_URL=https://standalone.2smart.com
SMART_STATIC_BASE_PATH=releases

error_handler() {
	error_message=$1

	if [ -z "$error_message" ]; then
		error_message="Unknown error..."
	fi

	echo ""
	echo "### ERROR: $error_message"
	echo ""

	exit 1
}

get_docker_root_dir() {
	sh_c=$(root_exec_cmd)
	docker_root_dir=`$sh_c "docker info | grep \"Docker Root Dir\" | cut -c 19-"`

	if [ ! -d "$docker_root_dir" ]; then
		docker_root_dir=/var/lib/docker
	fi

	echo $docker_root_dir
}

## Detect system timezone
detect_timezone() {
    if [ -f /etc/timezone ]; then
        DETECTED_TIMEZONE=`cat /etc/timezone`
    elif filename=$(readlink /etc/localtime); then
        DETECTED_TIMEZONE=${filename#*zoneinfo/}
    fi
}

is_docker_installed() {
	if command_exists docker && [ -e /var/run/docker.sock ]; then
		return 0
	else
		return 1
	fi
}

## Check system command
command_exists() {
	command -v "$@" > /dev/null 2>&1
}

## Get OS distribution
get_distribution() {
	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	elif command_exists uname; then
		lsb_dist=$(uname)
	fi
	# Returning an empty string here should be alright since the
	# case statements don't act unless you provide an actual value
	echo "$lsb_dist"
}

is_install_docker_skipped() {
	if [ -z "$SKIP_DOCKER_INSTALL" ];then
		return 1
	else
		return 0
	fi
}

get_user() {
	echo "$(id -un 2>/dev/null || true)"
}

root_exec_cmd() {
	user="$( get_user )"

	sh_c='sh -c'
	if [ "$user" != 'root' ]; then
		if command_exists sudo; then
			sh_c='sudo -E sh -c'
		elif command_exists su; then
			sh_c='su -c'
		else
			cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
			exit 1
		fi
	fi

	echo $sh_c
}


add_debian_backport_repo() {
	debian_version="$1"
	backports="deb http://ftp.debian.org/debian $debian_version-backports main"
	if ! grep -Fxq "$backports" /etc/apt/sources.list; then
		(set -x; $sh_c "echo \"$backports\" >> /etc/apt/sources.list")
	fi
}

# Check if this is a forked Linux distro
check_forked() {

	# Check for lsb_release command existence, it usually exists in forked distros
	if command_exists lsb_release; then
		# Check if the `-u` option is supported
		set +e
		lsb_release -a -u > /dev/null 2>&1
		lsb_release_exit_code=$?
		set -e

		# Check if the command has exited successfully, it means we're in a forked distro
		if [ "$lsb_release_exit_code" = "0" ]; then
			# Print info about current distro
			cat <<-EOF
			You're using '$lsb_dist' version '$dist_version'.
			EOF

			# Get the upstream release info
			lsb_dist=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'id' | cut -d ':' -f 2 | tr -d '[:space:]')
			dist_version=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'codename' | cut -d ':' -f 2 | tr -d '[:space:]')

			# Print info about upstream distro
			cat <<-EOF
			Upstream release is '$lsb_dist' version '$dist_version'.
			EOF
		else
			if [ -r /etc/debian_version ] && [ "$lsb_dist" != "ubuntu" ] && [ "$lsb_dist" != "raspbian" ]; then
				if [ "$lsb_dist" = "osmc" ]; then
					# OSMC runs Raspbian
					lsb_dist=raspbian
				else
					# We're Debian and don't even know it!
					lsb_dist=debian
				fi
				dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
				case "$dist_version" in
					10)
						dist_version="buster"
					;;
					9)
						dist_version="stretch"
					;;
					8|'Kali Linux 2')
						dist_version="jessie"
					;;
				esac
			fi
		fi
	fi
}

install_docker() {
    sh_c=$(root_exec_cmd)

    case "$lsb_dist" in
		ubuntu)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
		;;
		debian|raspbian)
			dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
			case "$dist_version" in
				10)
					dist_version="buster"
				;;
				9)
					dist_version="stretch"
				;;
				8)
					dist_version="jessie"
				;;
			esac
		;;
		centos)
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;
		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --release | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

	esac

    # Check if this is a forked Linux distro
	check_forked

	# CentOS 8 issue
	if [ "$lsb_dist" = "centos" ] && [ "$dist_version" = "8" ] && command_exists podman; then
		echo
		echo "WARNING: The latest release of the RHEL 8 / CentOS 8 has built in tool(podman) which is incompatible with docker"
		echo "    To run our application please install \"Docker\" manually or remove \"podman\"."
		echo "    You can run this script again after one of steps above."

		exit 1
	fi

	# Run setup for each distro accordingly
    case "$lsb_dist" in
		ubuntu|debian|raspbian)
			pre_reqs="apt-transport-https ca-certificates curl"
			if [ "$lsb_dist" = "debian" ]; then
				# libseccomp2 does not exist for debian jessie main repos for aarch64
				if [ "$(uname -m)" = "aarch64" ] && [ "$dist_version" = "jessie" ]; then
					add_debian_backport_repo "$dist_version"
				fi
			fi

			if ! command -v gpg > /dev/null; then
				pre_reqs="$pre_reqs gnupg"
			fi
			apt_repo="deb [arch=$(dpkg --print-architecture)] $DOWNLOAD_URL/linux/$lsb_dist $dist_version $CHANNEL"
			(
				$sh_c 'apt-get update -qq >/dev/null'
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pre_reqs >/dev/null"
				$sh_c "curl -fsSL \"$DOWNLOAD_URL/linux/$lsb_dist/gpg\" | apt-key add -qq - >/dev/null"
				$sh_c "echo \"$apt_repo\" > /etc/apt/sources.list.d/docker.list"
				$sh_c 'apt-get update -qq >/dev/null'
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				# Will work for incomplete versions IE (17.12), but may not actually grab the "latest" if in the test channel
				pkg_pattern="$(echo "$VERSION" | sed "s/-ce-/~ce~.*/g" | sed "s/-/.*/g").*-0~$lsb_dist"
				search_command="apt-cache madison 'docker-ce' | grep '$pkg_pattern' | head -1 | awk '{\$1=\$1};1' | cut -d' ' -f 3"
				pkg_version="$($sh_c "$search_command")"
				echo "INFO: Searching repository for VERSION '$VERSION'"
				echo "INFO: $search_command"
				if [ -z "$pkg_version" ]; then
					echo
					echo "ERROR: '$VERSION' not found amongst apt-cache madison results"
					echo
					exit 1
				fi
				search_command="apt-cache madison 'docker-ce-cli' | grep '$pkg_pattern' | head -1 | awk '{\$1=\$1};1' | cut -d' ' -f 3"
				# Don't insert an = for cli_pkg_version, we'll just include it later
				cli_pkg_version="$($sh_c "$search_command")"
				pkg_version="=$pkg_version"
			fi
			(
				if [ -n "$cli_pkg_version" ]; then
					$sh_c "apt-get install -y -qq --no-install-recommends docker-ce-cli=$cli_pkg_version >/dev/null"
				fi
				$sh_c "apt-get install -y -qq --no-install-recommends docker-ce$pkg_version >/dev/null"
			)
			;;
		centos|fedora)
			yum_repo="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE"
			if ! curl -Ifs "$yum_repo" > /dev/null; then
				echo "Error: Unable to curl repository file $yum_repo, is it valid?"
				exit 1
			fi
			if [ "$lsb_dist" = "fedora" ]; then
				pkg_manager="dnf"
				config_manager="dnf config-manager"
				enable_channel_flag="--set-enabled"
				disable_channel_flag="--set-disabled"
				pre_reqs="dnf-plugins-core"
				pkg_suffix="fc$dist_version"
			else
				pkg_manager="yum"
				config_manager="yum-config-manager"
				enable_channel_flag="--enable"
				disable_channel_flag="--disable"
				pre_reqs="yum-utils"
				pkg_suffix="el"
			fi
			(
				$sh_c "$pkg_manager install -y -q $pre_reqs"
				$sh_c "$config_manager --add-repo $yum_repo"

				if [ "$CHANNEL" != "stable" ]; then
					$sh_c "$config_manager $disable_channel_flag docker-ce-*"
					$sh_c "$config_manager $enable_channel_flag docker-ce-$CHANNEL"
				fi
				$sh_c "$pkg_manager makecache"
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				pkg_pattern="$(echo "$VERSION" | sed "s/-ce-/\\\\.ce.*/g" | sed "s/-/.*/g").*$pkg_suffix"
				search_command="$pkg_manager list --showduplicates 'docker-ce' | grep '$pkg_pattern' | tail -1 | awk '{print \$2}'"
				pkg_version="$($sh_c "$search_command")"
				echo "INFO: Searching repository for VERSION '$VERSION'"
				echo "INFO: $search_command"
				if [ -z "$pkg_version" ]; then
					echo
					echo "ERROR: '$VERSION' not found amongst $pkg_manager list results"
					echo
					exit 1
				fi
				search_command="$pkg_manager list --showduplicates 'docker-ce-cli' | grep '$pkg_pattern' | tail -1 | awk '{print \$2}'"
				# It's okay for cli_pkg_version to be blank, since older versions don't support a cli package
				cli_pkg_version="$($sh_c "$search_command" | cut -d':' -f 2)"
				# Cut out the epoch and prefix with a '-'
				pkg_version="-$(echo "$pkg_version" | cut -d':' -f 2)"
			fi
			(
				# install the correct cli version first
				if [ -n "$cli_pkg_version" ]; then
					$sh_c "$pkg_manager install -y -q docker-ce-cli-$cli_pkg_version"
				fi

				# CentOS 8 issue
				if [ "$lsb_dist" = "centos" ] && [ "$dist_version" = "8" ]; then
					$sh_c "$pkg_manager install --nobest -y -q docker-ce$pkg_version"
				else
					$sh_c "$pkg_manager install -y -q docker-ce$pkg_version"
				fi

				$sh_c "systemctl start docker"
			)
			;;
		*)
			echo
			echo "ERROR: Unsupported distribution '$lsb_dist'"
			echo
			exit 1
			;;
	esac

	post_installation || error_handler "Failed to perform post installation actions!"
}

install_docker_compose() {
	sh_c=$(root_exec_cmd)

	## Fedora ??/30/31 installing corrupted docker-compose from link
	## So it's different command to install docker-compose
	## https://forums.docker.com/t/error-in-docker-compose/76753/3
	case "$lsb_dist" in
		fedora)
			$sh_c "dnf -y install docker-compose"
		;;
		*)
			$sh_c "curl -sL \"https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose"
			$sh_c "chmod +x /usr/local/bin/docker-compose"
			$sh_c "ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose"
		;;
	esac
}

generate_password() {
	if command_exists openssl; then
		echo `openssl rand -base64 24`
	else
		echo `</dev/urandom tr -dc '12345!%qwertQWERTasdfgASDFGzxcvbZXCVB' | head -c24; echo ""`
	fi
}

append_env_conf() {
	sh_c=$(root_exec_cmd)

	$sh_c "echo '' >> .env"

	## overwrite env vars for custom DNS
	if [ "$DNS" != "localhost" ]; then
		$sh_c "echo 'SSL_DNS=$DNS' >> .env"
		$sh_c "echo 'MQTT_PROXY_URL=\"ws://$DNS/mqtt\"' >> .env"
		$sh_c "echo 'API_URL=\"http://$DNS\"' >> .env"
	fi

	## overwrite system timezone
	if [ "$SYSTEM_TZ" != "UTC" ]; then
		$sh_c "echo 'TIMEZONE=$SYSTEM_TZ' >> .env"
	fi

	## add root 2smart dir
	$sh_c "echo 'ROOT_DIR_2SMART=$ROOT_DIR_2SMART' >> .env"

	MYSQL_ROOT_PASSWORD=$(generate_password)
	MYSQL_PASSWORD=$(generate_password)
	MQTT_ROOT_PASSWORD=$(generate_password)
	JWT_TOKEN_SECRET=$(generate_password)
	SYSTEM_NOTIFICATIONS_HASH=$(generate_password)
	INFLUX_ROOT_PASSWORD=$(generate_password)

	$sh_c "echo 'MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD' >> .env"
	$sh_c "echo 'MYSQL_PASSWORD=$MYSQL_PASSWORD' >> .env"
	$sh_c "echo 'MQTT_ROOT_PASSWORD=$MQTT_ROOT_PASSWORD' >> .env"
	$sh_c "echo 'JWT_TOKEN_SECRET=$JWT_TOKEN_SECRET' >> .env"
	$sh_c "echo 'SYSTEM_NOTIFICATIONS_HASH=$SYSTEM_NOTIFICATIONS_HASH' >> .env"
	$sh_c "echo 'INFLUX_ROOT_PASSWORD=$INFLUX_ROOT_PASSWORD' >> .env"
}

remove_app_artifacts() {
	sh_c=$(root_exec_cmd)

    # append another artifacts which will be produced by app in the future here
	$sh_c "rm -rf .env docker-compose.yml ./system/"
}

handle_download_error() {
    remove_app_artifacts
	error_handler "Failed to download configuration file!"
}

download_2smart_env() {
	sh_c=$(root_exec_cmd)
	$sh_c "curl -sfX GET '$SMART_CONFIG_URL/$SMART_STATIC_BASE_PATH/.env' > .env" || handle_download_error
	append_env_conf
}

download_2smart_composer() {
	sh_c=$(root_exec_cmd)
	$sh_c "curl -sfX GET '$SMART_CONFIG_URL/$SMART_STATIC_BASE_PATH/docker-compose.yml' > docker-compose.yml" || handle_download_error
	$sh_c "chmod 664 docker-compose.yml"
}

download_2smart() {
	if [ -r docker-compose.yml ] || [ -r .env ]; then
		while true; do
			read -p "2smart settings found. Overwrite?[Y/n]" yn
			case $yn in
				[Yy]* )
                    remove_app_artifacts
					download_2smart_composer
					download_2smart_env
					SETTINGS_OVERWRITTEN=1
					break
				;;
				[Nn]* ) break;;
				* ) echo "Please answer yes or no.";;
			esac
		done
	fi

	if [ ! -r docker-compose.yml ]; then
		download_2smart_composer
	fi

	if [ ! -r .env ]; then
		download_2smart_env
	fi
}

install_curl() {
	sh_c=$(root_exec_cmd)

	case "$lsb_dist" in
		ubuntu|debian)
			$sh_c "apt-get update"
			$sh_c "apt-get install curl"
		;;
		centos|fedora)
			$sh_c "yum update"
			$sh_c "yum install curl"
		;;
		darwin)
			$sh_c "brew install curl"
		;;
		*)
			echo
			echo "Unable to install cURL!"
			exit 1
		;;

	esac
}

qst_skip_docker() {
	while true; do
		read -p "Do you want to skip docker installation and proceed?[Y/n]" yn
		case $yn in
			[Yy]* ) SKIP_DOCKER_INSTALL=1 ; break;;
			[Nn]* ) echo "Installation canceled!" ; exit;;
			* ) echo "Please answer yes or no.";;
		esac
	done
}

install_docker_and_compose() {
	## Install docker
	if ! is_docker_installed; then
		## When OS is not supported
		## Warning in qst_skip_docker
		if ! is_install_docker_skipped; then
			install_docker
		fi
	else
		echo "Docker already installed. Skipping..."
	fi

	## Install docker-compose
	if ! command_exists docker-compose; then
		install_docker_compose
	else
		echo "Docker compose already installed. Skipping..."
	fi
}

install_2smart() {
	# perform some very rudimentary platform detection
	lsb_dist=$( get_distribution )
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
    sh_c=$(root_exec_cmd)

	detect_timezone || error_handler "Failed to detect timezone!"

	if [ ! -z "$DETECTED_TIMEZONE" ]; then
		SYSTEM_TZ=$DETECTED_TIMEZONE
	fi

	if ! command_exists curl; then
		install_curl
	fi

	download_2smart || error_handler "Failed to download 2smart!"

	## Check distribution
	case "$lsb_dist" in
			ubuntu|debian|raspbian|centos|fedora)
				;;
			darwin)
				echo
				echo "ERROR: MacOS is not supported!"
				echo "       Can't install docker!"
				echo
				qst_skip_docker
				;;
			*)
				echo
				echo "ERROR: Unsupported distribution '$lsb_dist'"
				echo
				qst_skip_docker
				;;
	esac

	if ! is_docker_installed || ! command_exists docker-compose; then
		while true; do
			read -p "Do you want to install docker and docker-compose (Required to run 2smart)?[Y/n]" yn
			case $yn in
				[Yy]* )
					install_docker_and_compose || error_handler "Failed to install docker or docker-compose!"
					break
				;;
				[Nn]* ) echo "Docker installation skipped!" ; break;;
				* ) echo "Please answer yes or no.";;
			esac
		done
	fi

	## Add docker root dir to ENV file
	DOCKER_ROOT_DIR=$(get_docker_root_dir)
	$sh_c "echo 'DOCKER_DIR=$DOCKER_ROOT_DIR' >> .env"
	$sh_c "echo 'DOCKER_CONTAINERS=$DOCKER_ROOT_DIR/containers' >> .env"
}

docker_as_nonroot() {
	# user=$(get_user) # script executed from user
	user=${SUDO_USER:-$USER} # session user or user who run this script with sudo
	sh_c=$(root_exec_cmd)

	if [ "$user" != 'root' ]; then
		$sh_c "usermod -aG docker $user"

		RESTART_SESSION=1
	fi
}

docker_start_on_boot() {
	sh_c=$(root_exec_cmd)

	if ! command_exists systemctl; then
		case "$lsb_dist" in
			ubuntu|debian)
				$sh_c "apt-get install systemd"
				break
			;;
			*)
				SKIP_START_ON_BOOT_INSTALL=1
				echo
				echo "Unable to install systemd to perform this action. Skipping..."
				break
			;;
		esac
	fi

	## enable start docker on boot if systemctl exists
	if [ -z "$SKIP_START_ON_BOOT_INSTALL" ]; then
		$sh_c "systemctl enable docker"
	fi
}

get_local_ip() {
	case "$lsb_dist" in
		darwin)
			res=`ipconfig getifaddr en0`
		;;
		*)
			res=`hostname -I | awk '{print $1}'`
		;;
	esac

	echo $res
}

info_2smart() {
	LOCAL_IP=$(get_local_ip)

	TIMEZONE=$(grep TIMEZONE .env | tail -1 | xargs)
	TIMEZONE=${TIMEZONE#*=}

	echo
	echo
	echo "Credentials to admin panel:"
	echo "Login: admin"
	echo "Password: 2Smart"
	echo
	echo "Link to widgets screen: http://$LOCAL_IP"
	echo "Link to admin panel: http://$LOCAL_IP/admin"
	echo "Detected timezone - $TIMEZONE"
}

post_installation() {
	docker_as_nonroot
	docker_start_on_boot
}

wait_start() {
	echo "Starting 2smart..."
    # wait until backend server will start listen to $APP_PORT port
    $sh_c "docker exec -i client-dashboard-be sh -c 'while ! nc -z localhost \$APP_PORT; do sleep 0.1; done;'"
    # wait for EMQ X start("./bin/emqx_ctl status" command prints
    # current status of EMQ X and returns exit code 0 when EMQ X start running)
    $sh_c "docker exec -i 2smart-emqx sh -c 'while ! ./bin/emqx_ctl status &> /dev/null; do sleep 0.1; done;'"
    echo "2smart was started successfully"
}

post_install_2smart() {
    local project_docker_network="app-network"

    $sh_c "docker run --env-file .env --network=\"${CURRENT_DIR_NAME}_${project_docker_network}\" -it --rm ${SMART_POST_INSTALL_IMAGE}"
}

qst_post_install_2smart() {
	while true; do
		read -p "Do you want to install some additional services now?[Y/n]" yn
		case $yn in
			[Yy]* ) post_install_2smart ; break;;
			[Nn]* ) break;;
			* ) echo "Please answer yes or no.";;
		esac
	done
}

start_2smart() {
	if is_docker_installed && command_exists docker-compose; then
		sh_c=$(root_exec_cmd)

		$sh_c "docker-compose pull"
		$sh_c "COMPOSE_HTTP_TIMEOUT=200 docker-compose up -d"

		wait_start

		info_2smart

		# qst_post_install_2smart

		user=${SUDO_USER:-$USER} # session user or user who run this script with sudo
		# Re-evaluate session to use docker as non-root user
		# Copy root auth credentials to user's .docker dir
		if [ ! -z "$RESTART_SESSION" ]; then
			home_dir="/home/$user"
			docker_conf_dir="$home_dir/.docker"

			if [ "$lsb_dist" = "centos" ]; then
				$sh_c "cp -r /root/.docker $docker_conf_dir"
			fi

			(
				$sh_c "chown -R $user:$user $docker_conf_dir docker-compose.yml .env"
				$sh_c "chmod -R g+rwx $docker_conf_dir"
			) || true

            su -l $user # relogin to run new session under the "docker" group
		fi

		$sh_c "chown $user:$user docker-compose.yml .env"
	else
		echo "ERROR: Unable to start 2smart!"
		echo "Check if docker and docker-compose are installed."
	fi
}

install_2smart

start_2smart
