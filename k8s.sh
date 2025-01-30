#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error
set -o pipefail  # Return the exit status of the last command in the pipeline that failed

# Variables (customize as needed)
NAMESPACE="openshift-nfs-storage"
SERVER="x.x.x.238"
PATH_TO_TEST="/data/test"
PV_NAME="i-am-test-backup"
PVC_NAME="sysqa-backupsupport-pvc"
BACKUP_SIZE="500Gi"
STORAGE_CLASS="managed-test-storage"
TARGET_GI_INSTANCE="sysqagi"

# Step 1: Get nodes from cluster
# function get_nodes() {
#     echo "Getting nodes from the cluster..."
#     oc get node -o wide
# }

# Step 2: Configure NFS server
function configure_nfs_server() {
    echo "Configuring NFS server..."
    mkdir -p /data/test
    chmod 777 -R /data/test

    # Update /etc/exports
    cat <<EOF >> /etc/exports
# NFS export configuration for test
/data/test x.x.68.130(rw,sync,no_subtree_check,no_root_squash)
/data/test x.x.69.55(rw,sync,no_subtree_check,no_root_squash)
/data/test x.x.69.x7(rw,sync,no_subtree_check,no_root_squash)
/data/test x.x.69.141(rw,sync,no_subtree_check,no_root_squash)
/data/test x.x.70.112(rw,sync,no_subtree_check,no_root_squash)
/data/test x.x.71.56(rw,sync,no_subtree_check,no_root_squash)
/data/test x.x.71.145(rw,sync,no_subtree_check,no_root_squash)
/data/test x.x.71.149(rw,sync,no_subtree_check,no_root_squash)
/data/test x.x.71.156(rw,sync,no_subtree_check,no_root_squash)
/data/test x.x.77.143(rw,sync,no_subtree_check,no_root_squash)
EOF

    exportfs -a
    systemctl enable test-server
    systemctl start test-server
    systemctl status test-server
    shutdown -r now
}

# Step 3: Deploy test-client on the cluster
function deploy_test_client() {
  echo "Deploying test-client on the cluster..."
  if [ ! -d "kubernetes-incubator" ]; then
    git clone https://github.com/kubernetes-incubator/external-storage.git kubernetes-incubator
  else
    echo "Repository already cloned."
  fi

  if ! oc get namespace openshift-nfs-storage &>/dev/null; then
    oc create namespace openshift-nfs-storage
    echo "Namespace 'openshift-nfs-storage' created."
  else
    echo "Namespace 'openshift-nfs-storage' already exists."
  fi
  if ! oc get namespace openshift-nfs-storage -o jsonpath='{.metadata.labels.openshift\.io/cluster-monitoring}' | grep -q "true"; then
    oc label namespace openshift-nfs-storage "openshift.io/cluster-monitoring=true"
    echo "Label added to 'openshift-nfs-storage'."
  else
    echo "Label already set on 'openshift-nfs-storage'."
  fi
# Switch to the target namespace
  oc project openshift-nfs-storage
# Modify the RBAC and Deployment files with the current namespace if not already done
  NAMESPACE=$(oc project -q)
  if ! grep -q "namespace: $NAMESPACE" ./kubernetes-incubator/nfs-client/deploy/rbac.yaml; then
    sed -i'' "s/namespace:.*/namespace: $NAMESPACE/g" ./kubernetes-incubator/nfs-client/deploy/rbac.yaml
    echo "Updated namespace in rbac.yaml."
    oc create -f ./kubernetes-incubator/nfs-client/deploy/rbac.yaml
    echo "Created rbac.yaml."
  else
    echo "rbac.yaml already has the correct namespace."
  fi
  if ! grep -q "namespace: $NAMESPACE" ./kubernetes-incubator/nfs-client/deploy/deployment.yaml; then
    sed -i'' "s/namespace:.*/namespace: $NAMESPACE/g" ./kubernetes-incubator/nfs-client/deploy/deployment.yaml
    echo "Updated namespace in deployment.yaml."
    oc create -f ./kubernetes-incubator/nfs-client/deploy/deployment.yaml
    echo "Created deployment.yaml."
  else
    echo "deployment.yaml already has the correct namespace."
  fi
  # Add SCC only if not already added
  if ! oc get scc hostmount-anyuid -o json | jq -e '.users[] | select(. == "system:serviceaccount:'$NAMESPACE':nfs-client-provisioner")' > /dev/null; then
    oc adm policy add-scc-to-user hostmount-anyuid system:serviceaccount:$NAMESPACE:nfs-client-provisioner
    echo "SCC 'hostmount-anyuid' added to the service account."
  else
    echo "SCC 'hostmount-anyuid' already added to the service account."
  fi
}

# Step 4: Create Persistent Volume (PV)
function create_pv() {
    echo "Creating Persistent Volume..."
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  annotations:
    pv.kubernetes.io/provisioned-by: storage.io/nfs
  name: $PV_NAME
spec:
  accessModes:
  - ReadWriteMany
  capacity:
    storage: $BACKUP_SIZE
  nfs:
    path: /data/insights/backup-systest-longrunning
    server: $SERVER
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $STORAGE_CLASS
  volumeMode: Filesystem
EOF
}

# Step 5: Create Persistent Volume Claim (PVC)
function create_pvc() {
    echo "Creating Persistent Volume Claim..."
    cat <<EOF | oc apply -f -
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: $PVC_NAME
  annotations:
    volume.beta.kubernetes.io/storage-class: "$STORAGE_CLASS"
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: $BACKUP_SIZE
    claimRef:
      namespace: sysqa
      name: $PV_NAME
EOF
}

# Step 6: Patch resources
function patch_resources() {
    echo "Patching resources for backup support..."
    oc patch guardiuminsights $(oc get guardiuminsights -o jsonpath='{range.items[*]}{.metadata.name}') --type='json' -p '[{"op":"add","path":"/spec/guardiumInsightsGlobal/backupsupport","value":{"enabled":"true","name":"sysqa-backupsupport-pvc","size":"500Gi","storageClassName":"managed-test-storage"}}]'

    oc patch db2uinstance $(oc get guardiuminsights -o jsonpath='{range .items[*]}{.metadata.name}')-db2 --type='json' -p '[{"op":"add","path":"/spec/storage/3","value":{"name":"backup","claimName":"sysqa-backupsupport-pvc","spec":{"resources":{}},"type":"existing"}}]'
}

# Step 7: Start backup process
function start_backup() {
    echo "Starting backup process..."
    cat <<EOF | oc apply -f -
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
        size: $BACKUP_SIZE
        storageClassName: $STORAGE_CLASS
        volumeName: $PV_NAME
  targetGIInstance: $TARGET_GI_INSTANCE
EOF
}

# Main script execution
get_nodes
configure_nfs_server
deploy_test_client
create_pv
create_pvc
patch_resources
start_backup

echo "All steps completed successfully."
