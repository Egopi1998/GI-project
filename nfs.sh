#!/bin/bash

# we need configure NFS server as node, so below commands will run in nfs server 

NFS_SERVER_1="root@10.188.47.238"
NFS_SERVER_1_PASSWORD="bMccW2NgBLBw"
BACKUP_DIR_MAIN="/data/insights/"
BACKUP_DIR="/data/insights/3.6.0-backup/3.6.0-ga"
TIMESTAMP=$(date +%F-%H-%M)
SCRIPT_NAME=$(echo $0 | cut -d "." -f1)
LOGFILE=/tmp/$SCRIPT_NAME-$TIMESTAMP.log

# changing to the main directory

if [ "$PWD" = "${BACKUP_DIR}" ]; then
    echo "OK"
else
    cd $BACKUP_DIR_MAIN && 
    mkdir $BACKUP_DIR &&
    chmod 777 -R BACKUP_DIR 
    echo "Navigate to ${BACKUP_DIR_MAIN}"
fi





