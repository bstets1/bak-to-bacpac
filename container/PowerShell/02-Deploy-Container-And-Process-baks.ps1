<#
This will deploy the image to an Azure Container Instance Group 

which will process the backups in the storage account and create the bacpacs

It also has the code to upload the files from the onprem backup store to the fileshare for demos
#>

# Load Variables

# Make sure your prompt is at the root of the repository and run.

. .\container\PowerShell\variables.ps1

#region For demos to upload files to storage account

<#

$Files = Get-ChildItem $onprembackupdirectory\*.bak

$ctx = (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).Context

foreach ($file in $files) {
    Write-Host "Uploading $($File.FullName)"
    $SetAzFileContentParams = @{
        Context   = $ctx
        ShareName = $ShareName
        Source    = $file.FullName
        Path      = "$ShareFolderPath\$($File.Name)"
        Force     = $true
    }
    Set-AzStorageFileContent @SetAzFileContentParams
}

#>

#endregion


#region Create a new Azure Container Instance group 

#region Variables
$MSSQL_SA_PASSWORD = $containerSaPassword.GetNetworkCredential().Password
$ACRLoginServer = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName -Name $ACRName
$ACRLoginServer = $ACRLoginServer.LoginServer
$ACRUser = Get-AzKeyVaultSecret -VaultName $KVName  -Name 'acr-pull-user' -AsPlainText
$ACRPass = Get-AzKeyVaultSecret -VaultName $KVName -Name 'acr-pull-pass'
#$ACRPass = $ACRPass.SecretValue 
$StorageAcctKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value | ConvertTo-SecureString -AsPlainText -Force

#endregion

if (-not(Get-AzContainerGroup -ResourceGroupName $ResourceGroupName -Name $ContainerGroupName -ErrorAction SilentlyContinue)) {
    $port = New-AzContainerInstancePortObject -Port '1433' -Protocol 'TCP'
    $EnvVariable1 = New-AzContainerInstanceEnvironmentVariableObject -Name ACCEPT_EULA -Value Y 
    $EnvVariable2 = New-AzContainerInstanceEnvironmentVariableObject -Name MSSQL_SA_PASSWORD -SecureValue $MSSQL_SA_PASSWORD
    $EnvVariable3 = New-AzContainerInstanceEnvironmentVariableObject -Name MSSQL_PID -Value Enterprise
    $regCred = New-AzContainerGroupImageRegistryCredentialObject -Server $ACRLoginServer -Username $ACRUser -Password $ACRPass
    $volume = New-AzContainerGroupVolumeObject -Name $ShareName -AzureFileShareName $ShareName -AzureFileStorageAccountName $StorageAccountName -AzureFileStorageAccountKey $StorageAcctKey
    $mount = New-AzContainerInstanceVolumeMountObject -MountPath $VolumeMountPath -Name $ShareName
    $container = New-AzContainerInstanceObject -Name $ContainerGroupName -Image "$ACRLoginServer/$ACRPath" -EnvironmentVariable @($EnvVariable1, $EnvVariable2, $EnvVariable3)  -Port $port -RequestCpu 2 -RequestMemoryInGb 4 -VolumeMount $mount
    New-AzContainerGroup -ResourceGroupName $ResourceGroupName -Name $ContainerGroupName -Location $Location -Container $container -ImageRegistryCredential $regCred -OSType Linux -IPAddressType 'Public' -Volume $volume

    Write-Host "Container group ($ContainerGroupName) created."
}else {
    Write-Host "Container group ($ContainerGroupName) exists."
}

#endregion
<#
# Clean up 
Remove-AzContainerGroup `
    -ResourceGroupName $ResourceGroupName `
    -Name $ContainerGroupName
#>
