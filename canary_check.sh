#!/bin/bash

####README####
##To execute this script, need some parameter
##$DIR_DEPLOY/canary_check.sh <<service_name>> <<log_file_name>> <<number_of_looping_check>>
##############

function truncate_log() {
    LOG_NAME=$2
    DIR_HOST_LOGS=`logs_dir`
    sudo truncate -s 0 $DIR_HOST_LOGS/$LOG_NAME.log
}

function check_log() {
    SERV_NAME=$1
    LOG_NAME=$2
    REC=$3
    DIR_HOST_LOGS=`logs_dir`
    DIR_DEPLOY=`deploy_dir`
    if [[ $REC -eq 0 ]]; then
        echo "no panic found after $REC x 60 secs log checking"
        echo "applying deployment to latest"
        sh $DIR_DEPLOY/canary_apply.sh $SERV_NAME
    else
        echo "sleep for 60 secs then check log for panic ($REC)"
        sleep 60
        panic=`sudo cat $DIR_HOST_LOGS/$LOG_NAME.log | grep panic` # change panic with error logs your application
        if [[ -z $panic ]]; then
            echo "no panic found"
            check_log $SERV_NAME $LOG_NAME $(( $REC - 1 ))
        else
            echo "panic found!"
            echo $panic
            echo "applying rollback to last deployment"
            sh $DIR_DEPLOY/canary_rollback.sh $SERV_NAME
        fi
    fi
}

echo "=========== truncate log ===================="
truncate_log $1 $2 $3
echo "========== end of truncate log =================="

echo "=========== run canary test on new deployment ===================="
check_log $1 $2 $3
echo "========== end of canary test on new deployment =================="
