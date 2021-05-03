#!/bin/bash

# Log into the Azure CLI with the attached Managed Identity
echo "***Logging into Azure...***"
az login --identity

echo "***Logged into Azure successfully!***"

# Install Azure ML CLI
echo "***Installing Azure ML CLI...***"
az extension add -n azure-cli-ml

echo "***Azure ML CLI installed successfully!***"

#Set Azure subscription 
az account show --query '[name, id]'

# Input CI_INPUTDATA samples to create Compute Instance
# CI_INPUTDATA='[
#         {
#             "Name":"cpu-c2r14",
#             "Vm-size":"STANDARD_DS3_V2",
#             "Resource-group":"mtcs-dev-aml-rg",
#             "Workspace-name":"mtcs-dev-aml",
#             "Subnet-name": "subnet-01",
#             "Vnet-name": "vnet-01",
#             "Vnet-resouregroup-name": "mtcs-dev-ntwk-rg",
#             "TenantID":"########-b5f3-426e-b933-b1fe7cddcd63",
#             "UserID":"########-86c4-4504-a9df-6dad6a918702"
#         },
#         {
#             "Name":"azmlci01",
#             "Vm-size":"STANDARD_DS3_V2",
#             "Resource-group":"mtcs-dev-aml-rg",
#             "Workspace-name":"mtcs-dev-aml",
#             "TenantID":"########-b5f3-426e-b933-b1fe7cddcd63",
#             "UserID":"########-86c4-4504-a9df-6dad6a918702"
#         }
#     ]'

echo "________________________________________"
echo "New CI list as follows:"
echo $CI_INPUTDATA | jq -r '.[]'
echo "________________________________________"

if [[ ! -z "${CI_INPUTDATA}" ]];
then
    for item in $(echo $CI_INPUTDATA | jq -c '.[]')
    do
        vnetkeyexists=$(echo $item | jq '. | keys')
        
        if [[ $vnetkeyexists = *Vnet-resourcegroup-name* ]]
        then
            declare name
            declare vmsize
            declare resourcegroupname
            declare workspacename
            declare vnetname
            declare subnetname
            declare vnetresourcegroupname
            declare tenantid
            declare userid

            name=$(echo "${item}" | jq -r '.Name')
            vmsize=$(echo "${item}" | jq -r '."Vm-size"')
            resourcegroupname=$(echo "${item}" | jq -r '."Resource-group"')
            workspacename=$(echo "${item}" | jq -r '."Workspace-name"')
            vnetname=$(echo "${item}" | jq -r '."Vnet-name"')
            subnetname=$(echo "${item}" | jq -r '."Subnet-name"')
            vnetresourcegroupname=$(echo "${item}" | jq -r '."Vnet-resourcegroup-name"')
            tenantid=$(echo "${item}" | jq -r '.TenantID')
            userid=$(echo "${item}" | jq -r '.UserID')

            # If specified name of VM is already in use  following command won't work
            az ml computetarget create computeinstance -n $name --vm-size $vmsize -w $workspacename -g $resourcegroupname --vnet-name $vnetname --subnet-name $subnetname --vnet-resourcegroup-name $vnetresourcegroupname --user-tenant-id $tenantid --user-object-id $userid --no-wait -v

            echo "Compute Instance creation process completed"

        else
            declare name
            declare vmsize
            declare resourcegroupname
            declare workspacename
            declare tenantid
            declare userid

            name=$(echo "${item}" | jq -r '.Name')
            vmsize=$(echo "${item}" | jq -r '."Vm-size"')
            resourcegroupname=$(echo "${item}" | jq -r '."Resource-group"')
            workspacename=$(echo "${item}" | jq -r '."Workspace-name"')
            tenantid=$(echo "${item}" | jq -r '.TenantID')
            userid=$(echo "${item}" | jq -r '.UserID')

            # If specified name of VM is already in use  following command won't work
            az ml computetarget create computeinstance -n $name --vm-size $vmsize -w $workspacename -g $resourcegroupname --user-tenant-id $tenantid --user-object-id $userid --no-wait -v

            echo "Compute Instance creation process completed"

        fi
    done
else
    echo "There is no new request to create Compute Instance"

fi

exit 0
