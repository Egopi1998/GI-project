#!/bin/bash

LOGFILE="/var/log/nfs_backup_setup.log"
NFS_SERVER="10.188.47.238"   # Update this with your NFS server IP
NFS_PATH="/data/insights/3.6.0-backup/3.6.0-ga"
PV_NAME="i-am-nfs-backup"
PVC_NAME="sysqa-backupsupport-pvc"
NAMESPACE="sysqa"
STORAGE_CLASS="managed-nfs-storage"

log() {
    echo "$(date) - $1" | tee -a $LOGFILE
}

check_command() {
    if [ $? -ne 0 ]; then
        log "Error: $1"
        exit 1
    fi
}

setup_nfs_server() {
    log "Setting up NFS server..."
    mkdir -p $NFS_PATH
    chmod 777 -R $NFS_PATH

    echo "$NFS_PATH *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    exportfs -a
    systemctl enable nfs-server
    systemctl start nfs-server
    systemctl status nfs-server
    check_command "NFS server setup failed."
}

deploy_nfs_on_cluster() {
    log "Deploying NFS on OpenShift cluster..."
    git clone https://github.com/kubernetes-incubator/external-storage.git kubernetes-incubator
    oc create namespace openshift-nfs-storage
    oc label namespace openshift-nfs-storage "openshift.io/cluster-monitoring=true"
    oc project openshift-nfs-storage
    cd kubernetes-incubator/nfs-client/

    NAMESPACE=$(oc project -q)
    sed -i'' "s/namespace:.*/namespace: $NAMESPACE/g" ./deploy/rbac.yaml
    sed -i'' "s/namespace:.*/namespace: $NAMESPACE/g" ./deploy/deployment.yaml

    oc create -f deploy/rbac.yaml
    oc adm policy add-scc-to-user hostmount-anyuid system:serviceaccount:$NAMESPACE:nfs-client-provisioner

    sed -i'' "s|storage.io/nfs|storage.io/nfs|g" deploy/class.yaml
    sed -i'' "s|10.188.47.238|$NFS_SERVER|g" deploy/deployment.yaml
    sed -i'' "s|/data/insights/3.6.0-backup/3.6.0-ga|$NFS_PATH|g" deploy/deployment.yaml

    oc create -f deploy/class.yaml
    oc create -f deploy/deployment.yaml
    check_command "NFS deployment failed."
}

create_pv() {
    log "Creating Persistent Volume (PV)..."
    cat <<EOF > backuppv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV_NAME
  annotations:
    pv.kubernetes.io/provisioned-by: storage.io/nfs
spec:
  accessModes:
  - ReadWriteMany
  capacity:
    storage: 500Gi
  nfs:
    path: $NFS_PATH
    server: $NFS_SERVER
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $STORAGE_CLASS
  volumeMode: Filesystem
EOF

    oc apply -f backuppv.yaml
    check_command "PV creation failed."
}

create_pvc() {
    log "Creating Persistent Volume Claim (PVC)..."
    cat <<EOF > backuppvc.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
  annotations:
    volume.beta.kubernetes.io/storage-class: "$STORAGE_CLASS"
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 500Gi
EOF

    oc apply -f backuppvc.yaml
    check_command "PVC creation failed."
}

patch_resources() {
    log "Patching OpenShift resources..."
    oc patch guardiuminsights $(oc get guardiuminsights -o jsonpath='{.items[0].metadata.name}') --type='json' -p '[{"op":"add","path":"/spec/guardiumInsightsGlobal/backupsupport","value":{"enabled":"true","name":"'$PVC_NAME'","size":"1000Gi","storageClassName":"'$STORAGE_CLASS'"}}]'
    
    oc patch db2uinstance $(oc get guardiuminsights -o jsonpath='{.items[0].metadata.name}')-db2 --type='json' -p '[{"op":"add","path":"/spec/storage/3","value":{"name":"backup","claimName":"'$PVC_NAME'","spec":{"resources":{}},"type":"existing"}}]'
    
    oc patch $(oc get mongodbcommunity -oname) --type='json' -p '[{"op":"add","path":"/spec/statefulSet/spec/template/spec/volumes","value":[{"name":"gi-backup-support-mount","persistentVolumeClaim":{"claimName":"'$PVC_NAME'"}}]}]'
    
    oc patch sts $(oc get guardiuminsights -o jsonpath='{.items[0].metadata.name}')-postgres-keeper --type='json' -p '[{"op":"add","path":"/spec/template/spec/volumes/2","value":{"name":"gi-postgres-backup","persistentVolumeClaim":{"claimName":"'$PVC_NAME'"}}},{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/3","value":{"mountPath":"/opt/data/backup","name":"gi-postgres-backup"}}]'
    
    check_command "Resource patching failed."
}

start_backup() {
    log "Starting backup..."
    cat <<EOF > backup_start.yaml
apiVersion: gi.ds.isc.ibm.com/v1
kind: Backup
metadata:
  name: gi-backup
spec:
  gi-backup:
    cronjob:
      schedule: "*/5 * * * *"
    insightsEnv:
      RETENTION_FULL_BACKUP_IN_DAYS: 0
      FREQUENCY_FULL_BACKUP_IN_DAYS: 2
      FREQUENCY_FULL_BACKUP_IN_INC_COUNT: 2
      RESUME_FULL_BACKUP_ON_FAILURE: true
    persistentVolumesClaims:
      backup:
        name: $PVC_NAME
        size: 500Gi
        storageClassName: $STORAGE_CLASS
        volumeName: $PV_NAME
  targetGIInstance: sysqagi
EOF

    oc apply -f backup_start.yaml
    check_command "Backup initiation failed."
}

check_status() {
    log "Checking backup status..."
    oc get backup
    oc describe backup gi-backup
    oc get pods | grep backup
}

main() {
    log "Starting NFS Backup Setup..."
    setup_nfs_server
    deploy_nfs_on_cluster
    create_pv
    create_pvc
    patch_resources
    start_backup
    check_status
    log "NFS Backup Setup Completed Successfully."
}

main
