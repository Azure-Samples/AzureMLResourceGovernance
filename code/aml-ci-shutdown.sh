#!/bin/bash

# Log into the Azure CLI with the attached Managed Identity
echo "***Logging into Azure...***"
az login --identity

echo "***Logged into Azure successfully!***"

# Install Azure ML CLI
echo "***Installing Azure ML CLI...***"
az extension add -n azure-cli-ml

echo "***Azure ML CLI installed successfully!***"

# Instantiate resource groups array and populate it
declare -a rgs

for rg in $(az group list --query [].name -o tsv)
do
    rgs+=(${rg})
done

echo "The following Resource Groups will be interrogated for Azure ML Workspaces...***"
for rg in "${rgs[@]}"
do
    echo $rg
done

# Iterate through resource groups array, search for azure ml workspaces, and stop any currently running instances
for rg in "${rgs[@]}"
do
    # Instantiate workspaces array
    declare -a ws

    for w in $(az ml workspace list -g $rg --query [].workspaceName -o tsv)
    do
        ws+=(${w})
    done

    # Check to see if workspaces array has items, if so proceed with stop process, else nothing left to do
    if ! (( ${#ws[@]} > 0 ));
    then
        echo "***No Workspaces were found in Resource Group: $rg, proceeding to next Resource Group...***"

    else
        echo "***The following Workspaces were found in Resource Group: $rg, checking to see if there are any running Compute Instances...***"
        for w in "${ws[@]}"
        do
            echo $w
        done

        # Iterate over the workspaces array and perform compute instance shutdown as needed
        for w in "${ws[@]}"
        do
            # Instantiate full compute instance array
            declare -a cifull

            # Populate full compute instance array with all running compute instances
            for ci in $(az ml computetarget list -w $w -g $rg -v --query "[?properties.computeType=='ComputeInstance' && properties.status.state=='Running'].name" -o tsv)
            do 
                cifull+=(${ci})
            done

            # Check to see if array has items, if so proceed with stop process, else nothing left to do
            if ! (( ${#cifull[@]} > 0 ));
            then
                echo "***There are currently no running Compute instances in Workspace: $w***"
                echo "***Compute Instance stop process complete for Workspace: $w***"

            else
                echo "***The following running Compute Instances were found in Workspace: $w..."
                for ci in "${cifull[@]}"
                do
                    echo $ci
                done

                if [[ -z "${CI_EXCEPTION}" ]];
                then
                    echo "***No exceptions were found, proceeding with stop command against the following running Compute Instances in Workspace $w...***"
                    for ci in "${cifull[@]}"
                    do
                        echo $ci
                    done

                    # Perform compute instance stop against full compute instance array
                    for ci in "${cifull[@]}"
                    do
                        az ml computetarget computeinstance stop -n $ci -w $w -g $rg
                        echo "***Compute Instance: $ci has been stopped successfully***"
                    done
                    echo "***Compute Instance stop process complete for Workspace: $w***"

                else
                    # Instantiate compute instance exception array
                    declare -a ciex

                    # Capture JSON object from ENV and store in compute instance exception array
                    for row in $(echo $CI_EXCEPTION | jq -r '.vmname[]')
                    do
                        ciex+=(${row})
                    done

                    # Display compute instance exception array
                    echo "***Compute Instance exception list is as follows:***"
                    for ci in "${ciex[@]}"
                    do
                        echo $ci
                    done
                    
                    # Instantiate final compute instance array
                    declare -a cifinal

                    # Populate final list array
                    for i in "${cifull[@]}"
                    do
                        skip=
                        for j in "${ciex[@]}"
                        do
                            [[ $i == $j ]] && { skip=1; break; }
                        done
                        [[ -n $skip ]] || cifinal+=(${i})
                    done

                    # Display final list array
                    echo "***Running Compute Instances to be stopped in Workspace: $w***"
                    for ci in "${cifinal[@]}"
                    do
                        echo $ci
                    done

                    # Perform compute instance stop
                    for ci in "${cifinal[@]}"
                    do
                        az ml computetarget computeinstance stop -n $ci -w $w -g $rg
                        echo "***Compute Instance: $ci has been stopped successfully***"
                    done

                    unset ciex
                    
                    unset cifinal

                    echo "***Compute Instance stop process complete for Workpace: $w***"

                fi
            fi

            unset cifull
            
        done
    fi

    unset ws

done

echo "***Compute Instance stop process completed across all Resource Groups/Workspaces successfully***"

exit 0
