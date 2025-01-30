#!/bin/bash

# Set Variables
NAMESPACE="sysqa"  # Update as needed
TARGET_INSTANCE="sysqagi"  # Update as needed
PVC_NAME="sysqa-backupsupport-pvc"
DATA_DIR="gi-backup-cp-console-sysqa-sysqagi-2024-05-08-1945"  # Update as needed

echo "Step 1: Stopping existing backup..."
BACKUP_NAME=$(oc get backup -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
if [ -n "$BACKUP_NAME" ]; then
    oc delete backup $BACKUP_NAME -n $NAMESPACE
    echo "Deleted backup: $BACKUP_NAME"
else
    echo "No active backup found."
fi

echo "Step 2: Creating restore YAML..."
cat <<EOF > start-restore-pvc.yaml
apiVersion: gi.ds.isc.ibm.com/v1
kind: Restore
metadata:
  name: gi-restore
spec:
  targetGIInstance: $TARGET_INSTANCE
  gi-restore:
    insightsEnv:
      DATA_DIR: $DATA_DIR
    volumes:
      restore:
        sourceName: $PVC_NAME
EOF

echo "Step 3: Applying restore configuration..."
oc apply -f start-restore-pvc.yaml -n $NAMESPACE

echo "Step 4: Verifying restore process..."
oc get restore -n $NAMESPACE
oc describe restore gi-restore -n $NAMESPACE
oc get pods -n $NAMESPACE | grep restore

echo "Restore process initiated successfully!"
