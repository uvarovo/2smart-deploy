#!/bin/bash

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

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

# Prefer docker compose v2, fall back to legacy docker-compose v1.
compose_cmd() {
	if docker compose version >/dev/null 2>&1; then
		echo "docker compose"
	elif command_exists docker-compose; then
		echo "docker-compose"
	else
		echo ""
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

ensure_env_var() {
	sh_c=$(root_exec_cmd)
	key=$1
	default_value=$2

	if ! $sh_c "grep -qE '^${key}=' '$ENV_FILE_PATH'"; then
		$sh_c "echo '' >> $ENV_FILE_PATH"
		$sh_c "echo '# Added by update_2smart.sh' >> $ENV_FILE_PATH"
		$sh_c "echo '${key}=${default_value}' >> $ENV_FILE_PATH"
	fi
}

add_new_variables() {
    sh_c=$(root_exec_cmd)
    ROOT_DIR_2SMART=$(dirname "$(realpath $0)")
	DOCKER_ROOT_DIR=$(get_docker_root_dir)

	# Back up .env before mutating it.
	$sh_c "cp $ENV_FILE_PATH $ROOT_DIR_2SMART/.env.update.bak"

    ensure_env_var "BACKUPS_MEMORY_LIMIT" "2gb"
    ensure_env_var "ROOT_DIR_2SMART" "$ROOT_DIR_2SMART"
    ensure_env_var "MQTT_CACHE_LIMIT" "15000"
    ensure_env_var "DOCKER_DIR" "$DOCKER_ROOT_DIR"
    ensure_env_var "DOCKER_CONTAINERS" "$DOCKER_ROOT_DIR/containers"
    ensure_env_var "IGNORE_YML_FILES" ""
    ensure_env_var "INFLUX_ROTATION_DAYS" "180"
    ensure_env_var "SCENARIO_RUNNER_TAG" "latest"
    ensure_env_var "SCENARIO_RUNNER_MEMORY_LIMIT" "12g"
    ensure_env_var "SCENARIO_RUNNER_NODE_OPTIONS" "--max-old-space-size=8192"
    ensure_env_var "MQTT_BROKER_URI" '"wss://${HOSTNAME}/mqtt"'
    ensure_env_var "API_URI" '"https://${HOSTNAME}"'
    ensure_env_var "BACKUP_API_URI" '"https://${HOSTNAME}"'
    ensure_env_var "BRIDGE_IDS" ""
}

get_variable() {
    if [ -z $1 ]; then
        echo ""
    fi

	res=$(grep $1 $ENV_FILE_PATH | tail -1 | cut -d '=' -f2)

    echo $res
}

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

backup_docker_compose() {
	sh_c=$(root_exec_cmd)
	$sh_c "cp $DOCKER_COMPOSE_FILE_PATH $ROOT_DIR_2SMART/docker-compose.yml.copy"
}

download_2smart_compose() {
	# Patched for uvarovo/2smart-deploy: pull latest docker-compose.yml and recovery scripts
	# from our own git repo instead of upstream standalone.2smart.com.
	# Requires this script to be run from inside a git clone.
	sh_c=$(root_exec_cmd)
	$sh_c "cd $ROOT_DIR_2SMART && git fetch --quiet origin && git checkout --quiet origin/main -- docker-compose.yml scripts/post-reboot-recovery.sh" \
		|| error_handler "Failed to update docker-compose.yml from git. Make sure $ROOT_DIR_2SMART is a git clone of uvarovo/2smart-deploy."
}

update_post_reboot_recovery() {
	sh_c=$(root_exec_cmd)
	script_src="$ROOT_DIR_2SMART/scripts/post-reboot-recovery.sh"
	script_dst="$ROOT_DIR_2SMART/post-reboot-recovery.sh"

	if [ -r "$script_src" ]; then
		$sh_c "cp '$script_src' '$script_dst'"
		$sh_c "chmod +x '$script_dst'"
		if ! $sh_c "crontab -l 2>/dev/null | grep -qF '$script_dst'"; then
			(
				$sh_c "crontab -l 2>/dev/null || true"
				$sh_c "echo \"@reboot $script_dst >> $ROOT_DIR_2SMART/post-reboot-recovery.log 2>&1\""
			) | $sh_c "crontab -"
		fi
	fi
}

wait_start() {
	echo ""
	echo "Starting 2smart..."
	sleep 60
}

restart_2smart() {
	sh_c=$(root_exec_cmd)
	COMPOSE_BIN=$(compose_cmd)

	if [ -z "$COMPOSE_BIN" ]; then
		error_handler "docker compose (v2 plugin) or docker-compose is not installed."
	fi

	$sh_c "$COMPOSE_BIN -f $DOCKER_COMPOSE_FILE_PATH pull"
	$sh_c "$COMPOSE_BIN -f $DOCKER_COMPOSE_FILE_PATH down"
	$sh_c "COMPOSE_HTTP_TIMEOUT=200 $COMPOSE_BIN -f $DOCKER_COMPOSE_FILE_PATH up -d"

	wait_start
}

get_docker_root_dir() {
	sh_c=$(root_exec_cmd)
	docker_root_dir=`$sh_c "docker info | grep \"Docker Root Dir\" | cut -c 19-"`

	if [ ! -d "$docker_root_dir" ]; then
		docker_root_dir=/var/lib/docker
	fi

	echo $docker_root_dir
}

ROOT_DIR_2SMART=$(dirname "$(realpath $0)")

ENV_FILE_PATH="$ROOT_DIR_2SMART/.env"
DOCKER_COMPOSE_FILE_PATH="$ROOT_DIR_2SMART/docker-compose.yml"

backup_docker_compose || error_handler "docker-compose backup error!"

download_2smart_compose || error_handler "An error occurred while downloading docker-compose!"

add_new_variables || error_handler "An error occurred while adding new env variables!"

restart_2smart || error_handler "An error occurred while restarting 2smart!"

update_post_reboot_recovery || true

echo ""
echo "Success!"
echo "Old docker-compose file saved in - $ROOT_DIR_2SMART/docker-compose.yml.copy"
echo "Old .env file saved in - $ROOT_DIR_2SMART/.env.update.bak"
