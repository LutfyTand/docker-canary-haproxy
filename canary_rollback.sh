#!/bin/bash

####README####
##To execute this script, need some parameter
##$DIR_DEPLOY/canary_rollback.sh <<service-name>>
##############

weight1=0
weight2=0
port_one=`50001`
port_two=`50002`

function docker_stop() {
	SERV_NAME=$1
	PORT_DEPLOY=$2
	CONT_COUNT=`docker ps -f name=$SERV_NAME | grep -v grep | awk '{print $2}'| wc -l`
	echo "Stopping Docker Container"
	if [[ $CONT_COUNT > 1  ]]; then
		echo "more than 1 docker is running"
		echo "one more container running on port $PORT_DEPLOY"
		echo "stop old docker container on port $PORT_DEPLOY"
		if [[ $PORT_DEPLOY == "$port_one"  ]]; then
			CONT_NAME=`docker ps | grep $SERV_NAME | grep $port_one |awk '{print $1}'`
		else
			CONT_NAME=`docker ps | grep $SERV_NAME | grep $port_two |awk '{print $1}'`
		fi
		docker rm -f $CONT_NAME
	else
		echo "no more than 1 running docker"
	fi
}

function docker_remove_container() {
	echo "Docker: remove containers"
	SERV_NAME=$1
	CONT_NAME=`docker ps -a | grep $SERV_NAME | grep -v grep | awk '{print $1}'| wc -l`
	echo "Count : " $CONT_NAME " Container(s)"
	if [[ $CONT_NAME != 0 ]];then
		docker rm --force $(docker ps -a | grep $SERV_NAME | grep -v grep | awk '{print $1}')
	else
		echo "Nothing Docker Containers to be deleted."
	fi
}

function docker_remove_image() {
	echo "Docker: remove images untagged"
	SERV_NAME=$1
	CONT_NAME=`docker images -f "dangling=true" | grep $SERV_NAME | grep -v grep | awk '{print $3}' | wc -l`
	CONT_NAME_ALL=`docker images -f "dangling=true" | grep -v 'IMAGE' | awk '{print $3}' | wc -l`
	echo "Count $SERV_NAME: "$CONT_NAME " Image(s)"
	echo "Count ALL Untagged :"$CONT_NAME_ALL " Image(s)"

	### REMOVE UNTAGGED IMAGES WITH SERVERNAME
	if [[ $CONT_NAME != 0 ]];then
		docker rmi --force $(docker images -f "dangling=true" | grep $SERV_NAME | grep -v grep | awk '{print $3}')
	else
		echo "Nothing Image(s) to be deleted."
	fi

	### REMOVE ALL UNTAGGED IMAGES
	if [[ $CONT_NAME_ALL != 0 ]];then
		docker rmi --force $(docker images -f "dangling=true" | grep -v 'IMAGE'| awk '{print $3}')
	else
		echo "Nothing Untagged Image(s) to be deleted."
	fi

	### REMOVE ALL UNUSED IMAGES
	echo "Docker: remove images unused"
	docker image prune -af
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

	weight1=`echo "get weight $SERV_NAME/docker1" | socat stdio /var/run/hapee-lb.sock | cut -d' ' -f1`
	weight2=`echo "get weight $SERV_NAME/docker2" | socat stdio /var/run/hapee-lb.sock | cut -d' ' -f1`

	echo "[PORT $port_one] Traffic Set Weight: " $weight1
	echo "[PORT $port_two] Traffic Set Weight: " $weight2
}

function set_weight_docker_stable() {
	echo "Apply latest deploy after canary"
	SERV_NAME=$1
	get_weight1=$weight1
	get_weight2=$weight2

	if [[ $get_weight1 -eq 5 ]]; then
		echo "rollback trafic to deployment on port $port_one"
		echo "set server $SERV_NAME/docker1 weight 100" | socat stdio /var/run/hapee-lb.sock
		echo "set server $SERV_NAME/docker2 weight 0" | socat stdio /var/run/hapee-lb.sock
		sleep 10
		docker_stop $SERV_NAME $port_two
	elif [[ $get_weight2 -eq 5 ]]; then
		echo "rollback trafic to deployment on port $port_two"
		echo "set server $SERV_NAME/docker1 weight 0" | socat stdio /var/run/hapee-lb.sock
		echo "set server $SERV_NAME/docker2 weight 100" | socat stdio /var/run/hapee-lb.sock
		sleep 10
		docker_stop $SERV_NAME $port_one
	fi
}

function apply_rollback() {
	echo "Rollback deployment"
	SERV_NAME=$1
	get_weight_haproxy $SERV_NAME
	sleep 5
	set_weight_docker_stable $SERV_NAME $weight1 $weight2
	sleep 5
	get_weight_haproxy $SERV_NAME
	echo ">>>> Rollback success <<<<<"
}

echo "====== Rollback and remove canary container ======"
apply_rollback $1
echo " Docker Remove Untagged Image"
docker_remove_image $1