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

add_new_variables() {
    sh_c=$(root_exec_cmd)
    ROOT_DIR_2SMART=$(dirname "$(realpath $0)")
	DOCKER_ROOT_DIR=$(get_docker_root_dir)

    $sh_c "echo '' >> $ENV_FILE_PATH"
    $sh_c "echo 'BACKUPS_MEMORY_LIMIT=2gb' >> $ENV_FILE_PATH"
    $sh_c "echo 'ROOT_DIR_2SMART=$ROOT_DIR_2SMART' >> $ENV_FILE_PATH"
    $sh_c "echo 'MQTT_CACHE_LIMIT=10000' >> $ENV_FILE_PATH"
	$sh_c "echo 'DOCKER_DIR=$DOCKER_ROOT_DIR' >> $ENV_FILE_PATH"
	$sh_c "echo 'DOCKER_CONTAINERS=$DOCKER_ROOT_DIR/containers' >> $ENV_FILE_PATH"
	$sh_c "echo 'IGNORE_YML_FILES=' >> $ENV_FILE_PATH"
	$sh_c "echo 'INFLUX_ROTATION_DAYS=90' >> $ENV_FILE_PATH"
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
	sh_c=$(root_exec_cmd)
	$sh_c "curl https://standalone.2smart.com/releases/docker-compose.yml > $DOCKER_COMPOSE_FILE_PATH"
}

wait_start() {
	echo ""
	echo "Starting 2smart..."
	sleep 60
}

restart_2smart() {
	sh_c=$(root_exec_cmd)

	$sh_c "docker-compose -f $DOCKER_COMPOSE_FILE_PATH pull"
	$sh_c "docker-compose -f $DOCKER_COMPOSE_FILE_PATH down"
	$sh_c "COMPOSE_HTTP_TIMEOUT=200 docker-compose -f $DOCKER_COMPOSE_FILE_PATH up -d"

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

echo ""
echo "Success!"
echo "Old docker-compose file saved in - $ROOT_DIR_2SMART/docker-compose.yml.copy"
