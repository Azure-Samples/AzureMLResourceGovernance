###############################################################################################################
##
## Azure ML Compute Instance Manager Deployment Script
##
###############################################################################################################

# Set preference variables
$ErrorActionPreference = "Stop"

# Intake and set parameters
$parameters = Get-Content ./deployParams.json | ConvertFrom-Json
$containerInstanceCreateCpu = $parameters.containerInstanceCreateCpu
$containerInstanceCreateMemory = $parameters.containerInstanceCreateMemory
$containerInstanceStopCpu = $parameters.containerInstanceStopCpu
$containerInstanceStopMemory = $parameters.containerInstanceStopMemory
$location = $parameters.location
$logicAppCreateCount = $parameters.logicAppCreateCount
$logicAppCreateTimeout = $parameters.logicAppCreateTimeout
$logicAppStopCount = $parameters.logicAppStopCount
$logicAppStopTimeout = $parameters.logicAppStopTimeout
$logicAppStopTriggerHour = $parameters.logicAppStopTriggerHour
$logicAppStopTriggerMinute = $parameters.logicAppStopTriggerMinute
$managedResourceGroups = $parameters.managedResourceGroups
$Name = $parameters.Name.ToLower()
$logFile = "./deploy_$(get-date -format `"yyyyMMddhhmmsstt`").log"

# Validate name
Function ValidateName
{
    param (
        [ValidateLength(6,17)]
        [ValidatePattern('^(?!-)(?!.*--)[a-z]')]
        [parameter(Mandatory=$true)]
        [string]
        $Name
    )
}

ValidateName $Name

# Validate location
$validLocations = Get-AzLocation
Function ValidateLocation {
    if ($location -in ($validLocations | Select-Object -ExpandProperty Location)) {
        foreach ($l in $validLocations) {
            if ($location -eq $l.Location) {
                $script:locationName = $l.DisplayName
            }
        }
    }
    else {
        Write-Host "ERROR: Location provided is not a valid Azure Region!" -ForegroundColor red
        exit
    }
}

ValidateLocation $location

# Create resource group if it doesn't already exist
$rgcheck = Get-AzResourceGroup -Name "$Name-rg" -ErrorAction SilentlyContinue
if (!$rgcheck) {
    Write-Host "INFO: Creating new resource group: $Name-rg" -ForegroundColor green
    Write-Verbose -Message "Creating new resource group: $Name-rg"
    New-AzResourceGroup -Name "$Name-rg" -Location $location

}
else {
    Write-Warning -Message "Resource Group: $Name-rg already exists. Continuing with deployment..."

}

try {
    # Deploy ARM template for user assigned managed identity
    Write-Host "INFO: Deploying ARM template to create User Assigned Managed Identity" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM template to create User Assigned Managed Identity"
    $managedIdentityParams = @{
        'namePrefix' = "$Name"
    }
    New-AzResourceGroupDeployment `
    -Name "managedIdentityDeployment" `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./armTemplates/managedIdentity/azuredeploy.json `
    -TemplateParameterObject $managedIdentityParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy User Assigned Managed Identity ARM template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}

# iterate through array of managed resource groups and grant contributor rights for each to the managed identity via arm template
foreach ($item in $managedResourceGroups) {
    try {
        # Deploy ARM template for role assignments for managed identity
        Write-Host "INFO: Deploying ARM template to create Role Assignments for Managed Identity" -ForegroundColor green
        Write-Verbose -Message "Deploying ARM template to create Role Assignments for Managed Identity"
        $managedIdentityRoleAssignmentParams = @{
            'namePrefix' = "$Name"
        }
        New-AzResourceGroupDeployment `
        -Name "$item-RoleAssignmentDeployment" `
        -ResourceGroupName $item `
        -TemplateFile ./armTemplates/roleAssignments/managedIdentity/azuredeploy.json `
        -TemplateParameterObject $managedIdentityRoleAssignmentParams
    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Unable to deploy Role Assignments for managed Identity ARM template due to an exception, see $logFile for detailed information!" -ForegroundColor red
        exit
    
    }
}

try {
    # Deploy ARM template to create log analytics workspace
    Write-Host "INFO: Deploying ARM template to create Log Analytics Workspace" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM template to create Log Analytics Workspace"
    $workspaceParams = @{
        'namePrefix' = "$Name"
    }
    New-AzResourceGroupDeployment `
    -Name "workspaceDeployment" `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./armTemplates/logAnalyticsWorkspace/azuredeploy.json `
    -TemplateParameterObject $workspaceParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Log Analytics Workspace ARM template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}

try {
    # Deploy ARM template to create storage account, blob container, and file share
    Write-Host "INFO: Deploying ARM template to create Storage Account, Blob Container, and File Share" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM template to create Storage Account, Blob Container, and File Share"
    $storageParams = @{
        'namePrefix' = "$Name"
    }
    $storageAccountDeployment = New-AzResourceGroupDeployment `
    -Name "storageAccountDeployment" `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./armTemplates/storageAccount/azuredeploy.json `
    -TemplateParameterObject $storageParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Storage Account ARM template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit

}

# Get storage account context for artifact upload
Write-Host "INFO: Obtaining Storage Account context for artifact uploads..." -ForegroundColor green
Write-Verbose -Message "Obtaining Storage Account context for artifact uploads..."
$storageAccount = Get-AzStorageAccount -ResourceGroupName "$Name-rg" -Name "$($Name)stgacct"

if (!$storageAccount) {
    Write-Host "ERROR: Unable to obtain storage context, exiting script!" -ForegroundColor red
    exit

}
else {
    try {
        # Upload Azure ML Compute Instance management scripts to storage account
        Write-Host "INFO: Uploading Azure ML Compute Instance management scripts" -ForegroundColor green
        Write-Verbose -Message "Uploading Azure ML Compute Instance management scripts"
        Get-ChildItem `
        -File `
        -Path ./code/* | `
        ForEach-Object {
            Set-AzStorageFileContent `
            -ShareName "aci-code" `
            -Source "$_" `
            -Path "$($_.Name)" `
            -Context $storageAccount.Context `
            -Force
        }
    }
    catch {
        $_ | Out-File -FilePath $logFile -Append
        Write-Host "ERROR: Unable to upload Azure ML Compute Instance management scripts due to an exception, see $logFile for detailed information!" -ForegroundColor red
        exit

    }
}

try {
    # Deploy ARM template to create api connections
    Write-Host "INFO: Deploying ARM template to create API Connections" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM Template to create API Connections"
    $apiConnectionParams = @{
        'namePrefix' = "$Name";
        'storageAccountKey' = $storageAccountDeployment.Outputs.Values.Value
    }
    New-AzResourceGroupDeployment `
    -Name "apiConnectionDeployment" `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./armTemplates/apiConnection/azuredeploy.json `
    -TemplateParameterObject $apiConnectionParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy API Connections ARM Template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit
}

try {
    # Deploy ARM template to create logic app ci create workflow
    Write-Host "INFO: Deploying ARM template to create Logic App CI Create Workflow" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM Template to create Logic App CI Create workflow"
    $logicAppCreateParams = @{
        'containerInstanceCreateCpu' = "$containerInstanceCreateCpu";
        'containerInstanceCreateMemory' = "$containerInstanceCreateMemory";
        'logicAppCreateCount' = "$logicAppCreateCount";
        'logicAppCreateTimeout' = "$logicAppCreateTimeout";
        'namePrefix' = "$Name";
        'storageAccountKey' = $storageAccountDeployment.Outputs.Values.Value
    }
    New-AzResourceGroupDeployment `
    -Name "logicAppCreateDeployment" `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./armTemplates/logicApp/create/azuredeploy.json `
    -TemplateParameterObject $logicAppCreateParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Logic App CI Create ARM Template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit
}

try {
    # Deploy ARM template to create logic app ci stop workflow
    Write-Host "INFO: Deploying ARM template to create Logic App CI Stop Workflow" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM Template to create Logic App CI Stop workflow"
    $logicAppStopParams = @{
        'containerInstanceStopCpu' = "$containerInstanceStopCpu";
        'containerInstanceStopMemory' = "$containerInstanceStopMemory";
        'logicAppStopCount' = "$logicAppStopCount";
        'logicAppStopTimeout' = "$logicAppStopTimeout";
        'logicAppStopTriggerHour' = "$logicAppStopTriggerHour";
        'logicAppStopTriggerMinute' = "$logicAppStopTriggerMinute";
        'namePrefix' = "$Name";
        'storageAccountKey' = $storageAccountDeployment.Outputs.Values.Value
    }
    New-AzResourceGroupDeployment `
    -Name "logicAppStopDeployment" `
    -ResourceGroupName "$Name-rg" `
    -TemplateFile ./armTemplates/logicApp/stop/azuredeploy.json `
    -TemplateParameterObject $logicAppStopParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Logic App ARM Template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit
}

try {
    # Deploy ARM template to create role assignment for logic apps
    Write-Host "INFO: Deploying ARM template to create Role Assignments for Logic Apps" -ForegroundColor green
    Write-Verbose -Message "Deploying ARM Template to create Role Assignments for Logic Apps"
    $logicAppRoleAssignmentParams = @{
        'namePrefix' = "$Name"
    }
    New-AzDeployment `
    -Name "logicAppRoleAssignmentDeployment" `
    -Location "$location" `
    -TemplateFile ./armTemplates/roleAssignments/logicApp/azuredeploy.json `
    -TemplateParameterObject $logicAppRoleAssignmentParams
}
catch {
    $_ | Out-File -FilePath $logFile -Append
    Write-Host "ERROR: Unable to deploy Role Assignments for Logic Apps ARM Template due to an exception, see $logFile for detailed information!" -ForegroundColor red
    exit
}

Write-Host "INFO: Azure ML Compute Instance Manager deployment has completed successfully!" -ForegroundColor green
