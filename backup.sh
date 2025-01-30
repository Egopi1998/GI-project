#!/bin/bash

#making cluster as variable 
CLUSTER="oc login -u kubeadmin -p Q8a7j-AdEhS-nXd3b-896Wn --server=https://api.komal-bnr.cp.fyre.ibm.com:6443"
IP_LIST=$(oc get node -o wide | awk 'NR > 1 {print $6}')

$CLUSTER
while IFS= read -r line; do
    if [ $entry == $EXPORT_ENTRIES ]; then
        echo "Entry already exists"
    else
        echo "Entry does not exist"
    fi
done <<< "$EXPORT_ENTRIES"

# for entry in $EXPORT_ENTRIES; do
#     if [ $entry == $EXPORT_ENTRIES ]; then
#         echo "Entry already exists"
#     else
#         echo "Entry does not exist"
#     fi
#     sed -i "s|^${entry}|#&|" /etc/exports
# done




