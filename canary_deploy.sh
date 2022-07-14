#!/bin/bash

####README####
##To execute this script, need some parameter
##$DIR_DEPLOY/canary_deploy.sh <<service_name>> <<tagging/version>> <<service_port>> <<admin_port(optionals)>>
##############

aws_region=`xxxxx`
aws_ecr=`xxxx.dkr.ecr.$aws_region.amazonaws.com`
port_one=`50001`
port_two=`50002`
admin_port_one=`50003`
admin_port_two=`50004`
time_zone=`Asia/Jakarta`

function aws_docker_auth() {
	password=`aws ecr get-login-password --region $aws_region`
	docker login --password "$password" --username AWS "$aws_ecr"
}

function check_container() {
	echo "====Check Running Container===="
	SERV_NAME=$1
	IMAGE_TAGS=$2
	CONT_NAME=`docker ps |grep $SERV_NAME:$IMAGE_TAGS| wc -l`
	docker_check_digest=`docker images --digests |grep $SERV_NAME| grep $IMAGE_TAGS| awk '{print $3}'`
	ecr_check_digest=`aws ecr describe-images --repository-name $SERV_NAME --image-ids imageTag=$IMAGE_TAGS --query "sort_by(imageDetails,& imagePushedAt)[-1].imageDigest" --output text`

	if [[ $CONT_NAME != 0 ]]; then
		echo "Found: $CONT_NAME Container(s)"
		echo "Ooops, You're already using container with $SERV_NAME:$IMAGE_TAGS"
		echo "But wait, we're checking match Image Digest $SERV_NAME:$IMAGE_TAGS Docker & ECR"
		echo "Value of check ecr digest : $ecr_check_digest"
		if [[ $ecr_check_digest == $docker_check_digest ]]; then
			echo "AWS ECR & DOCKER IMAGE DIGEST ARE MATCH"
			echo ">>>> You're already in $SERV_NAME:$TAG_NAME <<<<<"
			echo "nothing to-do"
			exit 1
		else
			echo "We can't find the matches $SERV_NAME:$IMAGE_TAGS"
		fi
	else
		echo "We can't find image tags in running containers"
		echo "Tags: $SERV_NAME:$IMAGE_TAGS ready to pull from ECR"
	fi
}

function docker_pull() {
	SERV_NAME=$1
	TAG_NAME=$2
	echo "Docker: Pulling the version $TAG_NAME image from ECR Repository"
	docker pull $aws_ecr/$SERV_NAME:$TAG_NAME
}

function get_weight_haproxy() {
	echo "get weight haproxy"
	PORT_EXISTING1=`docker ps | grep $port_one`
	PORT_EXISTING2=`docker ps | grep $port_two`
	SERV_NAME=$1
	if [[ "$PORT_EXISTING1" ]]; then
		echo "Port : $port_one"
	elif [[ "$PORT_EXISTING2" ]]; then
		echo "Port : $port_two"
	fi

	get_weight1=`echo "get weight $SERV_NAME/docker1" |socat stdio /var/run/hapee-lb.sock`
	get_weight2=`echo "get weight $SERV_NAME/docker2" |socat stdio /var/run/hapee-lb.sock`

	echo "[PORT $port_one] Traffic Set Weight: " $get_weight1
	echo "[PORT $port_two] Traffic Set Weight: " $get_weight2
}

function set_weight_haproxy() {
	echo "set weight haproxy :" $1
	SERV_NAME=$1
	PORT_DEPLOY=$2

	if [[ $PORT_DEPLOY == "$port_one" ]]; then
		echo "Deploy Port : $port_one"
		echo "set server $SERV_NAME/docker1 weight 95" |socat stdio /var/run/hapee-lb.sock
		echo "set server $SERV_NAME/docker2 weight 5" |socat stdio /var/run/hapee-lb.sock
	elif [[ $PORT_DEPLOY == "$port_two" ]]; then
		echo "Deploy Port : $port_two"
		echo "set server $SERV_NAME/docker1 weight 5" |socat stdio /var/run/hapee-lb.sock
		echo "set server $SERV_NAME/docker2 weight 95" |socat stdio /var/run/hapee-lb.sock
	fi
}

function docker_run() {
	echo "Docker: Run"
	SERV_NAME=$1
	TAG_NAME=$2
	HA_PORT=$3
	ADMIN_PORT=$4
	CONTAINER_NAME="${SERV_NAME}-${TAG_NAME}"
	PORT_DEPLOY1=`docker ps | grep $port_one`
	PORT_DEPLOY2=`docker ps | grep $port_two`
	DIR_HOST_LOGS=`logs_dir`
	DIR_LOGS=`logs_dir`
	DIR_HOST_CONFIG=`config_dir`
	DIR_CONFIG=`config_dir`
	echo "Docker: Starting Run"
	if [[ -z "$PORT_DEPLOY1" ]]; then
		echo "starting docker container on port $port_one"
		echo "Information Weight: "
		get_weight_haproxy $SERV_NAME
		if [[ "$ADMIN_PORT" ]]; then
        	docker run -v $DIR_HOST_LOGS:$DIR_LOGS -v $DIR_HOST_CONFIG:$DIR_CONFIG -e TZ=$time_zone -d -p 0.0.0.0:$port_one:$HA_PORT -p 0.0.0.0:$admin_port_one:$ADMIN_PORT --log-driver=fluentd --log-opt tag=prod.$1 --log-opt fluentd-sub-second-precision="true" --name="${CONTAINER_NAME}.${port_one}" --restart=always -it $aws_ecr/$SERV_NAME:$TAG_NAME
		else
			docker run -v $DIR_HOST_LOGS:$DIR_LOGS -v $DIR_HOST_CONFIG:$DIR_CONFIG -e TZ=$time_zone -d -p 0.0.0.0:$port_one:$HA_PORT --log-driver=fluentd --log-opt tag=prod.$1 --log-opt fluentd-sub-second-precision="true" --name="${CONTAINER_NAME}.${port_one}" --restart=always -it $aws_ecr/$SERV_NAME:$TAG_NAME
        fi
		set_weight_haproxy $SERV_NAME $port_one
        get_weight_haproxy $SERV_NAME
        sleep 5
        set_weight_docker_stable $SERV_NAME $port_one
        sleep 5
        docker_stop $SERV_NAME $port_two
        get_weight_haproxy $SERV_NAME
	elif [[ -z "$PORT_DEPLOY2" ]]; then
		echo "starting docker container on port $port_two"
		echo "Information Weight: "
		get_weight_haproxy $SERV_NAME
		if [[ "$ADMIN_PORT" ]]; then
        	docker run -v $DIR_HOST_LOGS:$DIR_LOGS -v $DIR_HOST_CONFIG:$DIR_CONFIG -e TZ=$time_zone -d -p 0.0.0.0:$port_two:$HA_PORT -p 0.0.0.0:$admin_port_two:$ADMIN_PORT --log-driver=fluentd --log-opt tag=prod.$1 --log-opt fluentd-sub-second-precision="true" --name="${CONTAINER_NAME}.${port_two}" --restart=always -it $aws_ecr/$SERV_NAME:$TAG_NAME
		else
			docker run -v $DIR_HOST_LOGS:$DIR_LOGS -v $DIR_HOST_CONFIG:$DIR_CONFIG -e TZ=$time_zone -d -p 0.0.0.0:$port_two:$HA_PORT --log-driver=fluentd --log-opt tag=prod.$1 --log-opt fluentd-sub-second-precision="true" --name="${CONTAINER_NAME}.${port_two}" --restart=always -it $aws_ecr/$SERV_NAME:$TAG_NAME
        fi
        set_weight_haproxy $SERV_NAME $port_two
        get_weight_haproxy $SERV_NAME
        sleep 5
        set_weight_docker_stable $SERV_NAME $port_two
        sleep 5
        docker_stop $SERV_NAME $port_one
        get_weight_haproxy $SERV_NAME
	else
        echo "Both port is not available, aborting deployment."
        exit 1
    fi

    GET_RUNNING_TAG=`docker ps | grep $SERV_NAME | grep $TAG_NAME`
    if [[ -z "$GET_RUNNING_TAG" ]]; then
        echo "Docker with tag $TAG_NAME is not running, aborting deployment"
        exit 1
    else
        echo ">>>> You're now in $SERV_NAME:$TAG_NAME <<<<<"
	fi
}

echo "====== Docker Auth ======"
## AWS DOCKER AUTH ##
aws_docker_auth
## check running container ##
echo "====== Check Container ======"
check_container $1 $2
## docker pull new image ##
echo "====== Docker Pull ======"
docker_pull $1 $2
sleep 5
echo "====== Docker Pull ======"
## Docker Run ##
docker_run $1 $2 $3 $4