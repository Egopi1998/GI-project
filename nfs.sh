#!/bin/bash


set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error
set -o pipefail  # Return the exit status of the last command in the pipeline that failed

# we need configure NFS server as node, so below commands will run in nfs server 

# BACKUP_DIR_MAIN="/data/insights/"
# TIMESTAMP=$(date +%F-%H-%M)
# SCRIPT_NAME=$(echo $0 | cut -d "." -f1)
# LOGFILE=/tmp/$SCRIPT_NAME-$TIMESTAMP.log

USER="root" # NFS server username
PASSWORD="bMccW2NgBLBw" # NFS server password
HOST="10.188.47.238" # NFS server IP
BACKUP_DIR="/data/insights/3.6.0-backup/3.6.0-ga" # NFS server backup directory

CLUSTER="oc login -u kubeadmin -p Q8a7j-AdEhS-nXd3b-896Wn --server=https://api.komal-bnr.cp.fyre.ibm.com:6443"
IP_LIST=$(oc get node -o wide | awk 'NR > 1 {print $6}')

$CLUSTER

EXPORT_ENTRIES=""

i=1
# Loop through the list of IPs and dynamically assign them to variables
for ip in $IP_LIST; do
    eval "NODE_IP_$i=$ip"
    EXPORT_ENTRIES+="\n/${BACKUP_DIR} ${ip}(rw,sync,no_subtree_check,no_root_squash)"
    ((i++))
done

# Run the commands remotely using sshpass and SSH
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$HOST" << EOF
echo "Configuring NFS server..."
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    echo "Created $BACKUP_DIR directory"
else
    echo "$BACKUP_DIR already exists, skipping creation"
fi  
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    echo "Created $BACKUP_DIR directory"
    chmod 777 -R "$BACKUP_DIR"
    echo "Set permissions to 777 for $BACKUP_DIR"
else
    echo "$BACKUP_DIR already exists, ensuring permissions are set to 777"
    chmod 777 -R "$BACKUP_DIR"
fi
# Update /etc/exports
# NFS export configuration 
# Comment out any existing entries in /etc/exports that match the new entries
for entry in $EXPORT_ENTRIES; do
    sed -i "s|^${entry}|#&|" /etc/exports
done

cat <<EOL >> /etc/exports
$EXPORT_ENTRIES
EOL
# Apply the NFS export configuration
exportfs -a

# Enable and start the NFS server service if not already running
if ! systemctl is-enabled --quiet nfs-server; then
    systemctl enable nfs-server
    echo "Enabled nfs-server service"
fi

if ! systemctl is-active --quiet nfs-server; then
    systemctl start nfs-server
    echo "Started nfs-server service"
fi

# Check the status of the NFS server service
systemctl status nfs-server

# Reboot the system if necessary
echo "Rebooting the system to apply changes..."
# if grep -Fxq "$EXPORT_ENTRIES" /etc/exports; then
#     echo "No changes detected in /etc/exports, skipping reboot."
# else
#     echo "Changes detected in /etc/exports, rebooting the system..."
#     shutdown -r now
# fi
# Check if a reboot is needed (e.g., if /etc/exports changed)
if [ "$(diff /etc/exports /etc/exports.bak 2>/dev/null)" != "" ]; then
    cp /etc/exports /etc/exports.bak
    echo "Rebooting server to apply changes..."
    shutdown -r now
else
    echo "No changes detected, skipping reboot"
fi
EOF






