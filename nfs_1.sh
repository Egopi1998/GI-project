#!/bin/bash
set -euo pipefail

# --------------------------------------
# Configuration
# --------------------------------------
# USER="root"
# PASSWORD="bMccW2NgBLBw"
# HOST="10.188.47.238"
BACKUP_DIR="/data/insights/3.6.0-backup/3.6.0-ga"
# CLUSTER_LOGIN="oc login -u kubeadmin -p Q8a7j-AdEhS-nXd3b-896Wn --server=https://api.komal-bnr.cp.fyre.ibm.com:6443"
# EXPORTS_FILE="/etc/exports"

# # --------------------------------------
# # Cluster Login
# # --------------------------------------
# eval "$CLUSTER_LOGIN" || { echo "Cluster login failed"; exit 1; }

# # --------------------------------------
# # Get Node IPs
# # --------------------------------------
# IP_LIST=$(oc get node -o wide | awk 'NR > 1 {print $6}')
IP_LIST=(
  10.1.0.1
  10.1.0.2
  10.1.0.3
  10.1.0.4
  10.1.0.5
)
for ip in "${IP_LIST[@]}"; do
  echo "Processing IP: $ip"
done
# --------------------------------------
# Build EXPORT_ENTRIES
# --------------------------------------
EXPORT_ENTRIES=()
for ip in "${IP_LIST[@]}"; do
  # Format: "/backup/dir IP(options)"
  EXPORT_ENTRIES+=("${BACKUP_DIR} ${ip}(rw,sync,no_subtree_check,no_root_squash)")
done

EXPORTS_CONTENT=$(printf "%s\n" "${EXPORT_ENTRIES[@]}")
printf "\n%s\n" "${EXPORT_ENTRIES[@]}"

# # --------------------------------------
# # Remote NFS Configuration
# # --------------------------------------
# sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER@$HOST" /bin/bash << EOF
# set -euo pipefail

# # Create backup directory (with error handling)
# BACKUP_DIR="$BACKUP_DIR"
# if [ ! -d "\$BACKUP_DIR" ]; then
#     mkdir -p "\$BACKUP_DIR" || { echo "Failed to create \$BACKUP_DIR"; exit 1; }
#     chmod 777 "\$BACKUP_DIR"
#     echo "Created and set permissions for \$BACKUP_DIR"
# else
#     chmod 777 "\$BACKUP_DIR"  # Ensure permissions even if dir exists
#     echo "Confirmed permissions for \$BACKUP_DIR"
# fi

# # Backup /etc/exports before changes
# cp -p "$EXPORTS_FILE" "$EXPORTS_FILE.bak"

# # Comment out existing entries
# $(for entry in "${EXPORT_ENTRIES[@]}"; do
#   # Escape regex-sensitive characters
#   escaped_entry=\$(sed 's/[^^]/[&]/g; s/\^/\\^/g' <<< "$entry")
#   echo "sed -i 's|^\${escaped_entry}|#&|' $EXPORTS_FILE"
# done)

# # Add new entries
# cat <<EOL >> $EXPORTS_FILE
# $EXPORTS_CONTENT
# EOL

# # Apply NFS settings
# exportfs -a

# # Enable/start NFS server
# if ! systemctl is-enabled nfs-server &>/dev/null; then
#     systemctl enable nfs-server
# fi

# if ! systemctl is-active nfs-server &>/dev/null; then
#     systemctl start nfs-server
# fi

# # Reboot only if exports changed
# if ! diff -q "$EXPORTS_FILE" "$EXPORTS_FILE.bak" &>/dev/null; then
#     echo "Rebooting to apply changes..."
#     shutdown -r now
# else
#     echo "No changes detected; skipping reboot"
# fi
# EOF