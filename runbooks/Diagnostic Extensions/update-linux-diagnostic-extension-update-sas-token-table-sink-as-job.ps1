$connectionName = "AzureRunAsConnection"
try
{
	# Get the connection "AzureRunAsConnection "
	$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName

	"Logging in to Azure..."
	Add-AzAccount `
 		-ServicePrincipal `
 		-TenantId $servicePrincipalConnection.TenantId `
 		-ApplicationId $servicePrincipalConnection.ApplicationId `
 		-CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
}
catch {
	if (!$servicePrincipalConnection)
	{
		$ErrorMessage = "Connection $connectionName not found."
		throw $ErrorMessage
	} else {
		Write-Error -Message $_.Exception
		throw $_.Exception
	}
}

#Variables for script to run. Diagnostic extension will be set on all VM's in same region as storage account
$subID = ""
$storageAccountName = ""
$storageAccountResourceGroup = ""
$expiryTime = (Get-Date).AddDays(25)

#Select subscription
Select-AzSubscription -SubscriptionId $subID

#Gets storage account information
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroup -Name $storageAccountName

#Create SAS token for storage account 
$sasToken = New-AzStorageAccountSASToken -Service Blob,Table -ResourceType Service,Container,Object -Permission "racwdlup" -ExpiryTime $expiryTime -Context (Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroup -AccountName $storageAccountName).Context

#Configures storage account location
$storageLocation = $sa.Location

#Gets VM Object information in the same region as the storage account
$VMs = Get-AzVM | Where-Object { ($_.Location -eq $storageLocation) -and $_.ResourceGroupName -eq "Dusty"}

#Start folder  counter
$i = 1

foreach ($vm in $vms) {
	#Nulls the variables used to check if Windows or Linux
	$linuxExtensionCheck = $null
	$windowsExtensionCheck = $null

	#Checks if diagnostic extension is currently installed
	$linuxExtensionCheck = Get-AzVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name | Where-Object { $_.ExtensionType -eq "LinuxDiagnostic" }
	$windowsExtensionCheck = Get-AzVMExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name | Where-Object { $_.ExtensionType -eq "IaaSDiagnostics" }

	#Gets power status for VM
	$status = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status

	#Checks for Windows VM that does not contain the diagnostic extension and that it is turned on 
	if ($vm.StorageProfile.OsDisk.OsType -eq "Windows" -and $windowsExtensionCheck -eq $null -and $status.Statuses.displaystatus -contains "VM Running") {

		#Outputs name of VM we are working with
		Write-Output "Working on $($vm.Name)"

		#Output template to deploy
		if ((Test-Path c:\diag) -eq $false) {
			mkdir c:\diag
		}
		mkdir c:\diag\$i
		$template = @"
{
    "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "vmDiagnosticsStorageAccountName": {
            "type": "String",
            "metadata": {
                "description": "Unique DNS Name for the Storage Account where the Virtual Machine diagnostic information will be placed."
            }
        }
    },
    "variables": {
        "resourceId": "[resourceGroup().id]",
        "accountid": "[concat(variables('resourceId'),'/providers/Microsoft.Storage/storageAccounts/', parameters('vmDiagnosticsStorageAccountName'))]"
    },
    "resources": [
        {
            "type": "Microsoft.Compute/virtualMachines/extensions",
            "apiVersion": "2015-05-01-preview",
            "name": "$($vm.Name)/diag",
            "location": "$($vm.Location)",
            "properties": {
                "publisher": "Microsoft.Azure.Diagnostics",
                "type": "IaaSDiagnostics",
                "typeHandlerVersion": "1.5",
                "autoUpgradeMinorVersion": true,
                "settings": {
                    "WadCfg": {
                        "DiagnosticMonitorConfiguration": {
                            "overallQuotaInMB": 5120,
                            "Metrics": {
                                "resourceId": "/subscriptions/fbaa5434-4386-4e71-b45b-0030e15f73f8/resourceGroups/$($vm.ResourceGroupName)/providers/Microsoft.Compute/virtualMachines/$($vm.Name)",
                                "MetricAggregation": [
                                    {
                                        "scheduledTransferPeriod": "PT1H"
                                    },
                                    {
                                        "scheduledTransferPeriod": "PT1M"
                                    }
                                ]
                            },
                            "DiagnosticInfrastructureLogs": {
                                "scheduledTransferLogLevelFilter": "Error"
                            },
                            "PerformanceCounters": {
                                "scheduledTransferPeriod": "PT1M",
                                "PerformanceCounterConfiguration": [
                                    {
                                        "counterSpecifier": "\\Processor Information(_Total)\\% Processor Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Processor Information(_Total)\\% Privileged Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Processor Information(_Total)\\% User Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Processor Information(_Total)\\Processor Frequency",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\System\\Processes",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Process(_Total)\\Thread Count",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Process(_Total)\\Handle Count",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\System\\System Up Time",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\System\\Context Switches/sec",
                                        "unit": "CountPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\System\\Processor Queue Length",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\% Committed Bytes In Use",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Available Bytes",
                                        "unit": "Bytes",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Committed Bytes",
                                        "unit": "Bytes",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Cache Bytes",
                                        "unit": "Bytes",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Pool Paged Bytes",
                                        "unit": "Bytes",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Pool Nonpaged Bytes",
                                        "unit": "Bytes",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Pages/sec",
                                        "unit": "CountPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Memory\\Page Faults/sec",
                                        "unit": "CountPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Process(_Total)\\Working Set",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Process(_Total)\\Working Set - Private",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\% Disk Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\% Disk Read Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\% Disk Write Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\% Idle Time",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Bytes/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Read Bytes/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Write Bytes/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Transfers/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Reads/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Disk Writes/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk sec/Transfer",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk sec/Read",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk sec/Write",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk Queue Length",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk Read Queue Length",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Avg. Disk Write Queue Length",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\% Free Space",
                                        "unit": "Percent",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\LogicalDisk(_Total)\\Free Megabytes",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Bytes Total/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Bytes Sent/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Bytes Received/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Packets/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Packets Sent/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Packets Received/sec",
                                        "unit": "BytesPerSecond",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Packets Outbound Errors",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    },
                                    {
                                        "counterSpecifier": "\\Network Interface(*)\\Packets Received Errors",
                                        "unit": "Count",
                                        "sampleRate": "PT60S"
                                    }
                                ]
                            },
                            "WindowsEventLog": {
                                "scheduledTransferPeriod": "PT1M",
                                "DataSource": [
                                    {
                                        "name": "Application!*[System[(Level = 1 or Level = 2 or Level = 3)]]"
                                    },
                                    {
                                        "name": "Security!*[System[band(Keywords,4503599627370496)]]"
                                    },
                                    {
                                        "name": "System!*[System[(Level = 1 or Level = 2 or Level = 3)]]"
                                    }
                                ]
                            }
                        }
                    },
                    "StorageAccount": "[parameters('vmDiagnosticsStorageAccountName')]"
                },
                "protectedSettings": {
                    "storageAccountName": "[parameters('vmDiagnosticsStorageAccountName')]",
                    "storageAccountKey": "[listkeys(variables('accountid'), '2015-05-01-preview').key1]",
                    "storageAccountEndPoint": "https://core.windows.net/"
                }
            }
        }
    ]
}
"@ | Out-File c:\diag\$i\Metric_Template_Windows.json -Force -Confirm:$false -NoClobber

		#Deploy diagnostic setting
		New-AzResourceGroupDeployment -Name WindowsDiagnostic$i -ResourceGroupName $vm.ResourceGroupName -Mode Incremental -TemplateFile c:\diag\$i\Metric_Template_Windows.json -vmDiagnosticsStorageAccountName $sa.StorageAccountName -Force -Verbose -AsJob

		#Cleans up variables to save on socket limitation
		Remove-Variable linuxExtensionCheck -Force -Confirm:$false
		Remove-Variable windowsExtensionCheck -Force -Confirm:$false
		Remove-Variable status -Force -Confirm:$false
		Remove-Variable vm -Force -Confirm:$false
		[System.GC]::GetTotalMemory($true) | Out-Null

		#Starts sleep to allow connections to clean up
		Start-Sleep -s 10

		#Increase counter
		$i++
}
	
    #Checks for Linux VM that does not contain the diagnostic extension and that it is turned on 
	if ($vm.StorageProfile.OsDisk.OsType -eq "Linux" -and $linuxExtensionCheck -eq $null -and $status.Statuses.displaystatus -contains "VM Running") {

			#Outputs name of VM we are working with
			Write-Output "Working on $($vm.Name)"

			#Builds public settings information for metric onboarding 
			$publicSettings = "{
  'StorageAccount': '__DIAGNOSTIC_STORAGE_ACCOUNT__',
  'ladCfg': {
    'diagnosticMonitorConfiguration': {
      'eventVolume': 'Medium', 
      'metrics': {
        'metricAggregation': [
          {
            'scheduledTransferPeriod': 'PT1H'
          }, 
          {
            'scheduledTransferPeriod': 'PT1M'
          }
        ], 
        'resourceId': '__VM_RESOURCE_ID__'
      }, 
      'performanceCounters': {
        'performanceCounterConfiguration': [
          {
            'annotation': [
              {
               'displayName': 'Disk read guest OS', 
                'locale': 'en-us'
              }
            ], 
            'class': 'disk', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'readbytespersecond', 
            'counterSpecifier': '/builtin/disk/readbytespersecond', 
            'type': 'builtin', 
            'unit': 'BytesPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Disk writes', 
                'locale': 'en-us'
              }
            ], 
            'class': 'disk', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'writespersecond', 
            'counterSpecifier': '/builtin/disk/writespersecond', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Disk transfer time', 
                'locale': 'en-us'
              }
            ], 
            'class': 'disk', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'averagetransfertime', 
            'counterSpecifier': '/builtin/disk/averagetransfertime', 
            'type': 'builtin', 
            'unit': 'Seconds'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Disk transfers', 
                'locale': 'en-us'
              }
            ], 
            'class': 'disk', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'transferspersecond', 
            'counterSpecifier': '/builtin/disk/transferspersecond', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Disk write guest OS', 
                'locale': 'en-us'
              }
            ], 
            'class': 'disk', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'writebytespersecond', 
            'counterSpecifier': '/builtin/disk/writebytespersecond', 
            'type': 'builtin', 
            'unit': 'BytesPerSecond'
          }, 
          {
            'annotation': [
             {
                'displayName': 'Disk read time', 
                'locale': 'en-us'
              }
            ], 
            'class': 'disk', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'averagereadtime', 
            'counterSpecifier': '/builtin/disk/averagereadtime', 
            'type': 'builtin', 
            'unit': 'Seconds'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Disk write time', 
                'locale': 'en-us'
              }
            ], 
            'class': 'disk', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'averagewritetime', 
            'counterSpecifier': '/builtin/disk/averagewritetime', 
            'type': 'builtin', 
            'unit': 'Seconds'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Disk total bytes', 
                'locale': 'en-us'
              }
            ], 
            'class': 'disk', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'bytespersecond', 
            'counterSpecifier': '/builtin/disk/bytespersecond', 
            'type': 'builtin', 
            'unit': 'BytesPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Disk reads', 
                'locale': 'en-us'
              }
            ], 
            'class': 'disk', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'readspersecond', 
            'counterSpecifier': '/builtin/disk/readspersecond', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Disk queue length', 
                'locale': 'en-us'
              }
            ], 
            'class': 'disk', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'averagediskqueuelength', 
            'counterSpecifier': '/builtin/disk/averagediskqueuelength', 
            'type': 'builtin', 
            'unit': 'Count'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Network in guest OS', 
                'locale': 'en-us'
              }
            ], 
            'class': 'network', 
            'counter': 'bytesreceived', 
            'counterSpecifier': '/builtin/network/bytesreceived', 
            'type': 'builtin', 
            'unit': 'Bytes'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Network total bytes', 
                'locale': 'en-us'
              }
            ], 
            'class': 'network', 
            'counter': 'bytestotal', 
            'counterSpecifier': '/builtin/network/bytestotal', 
            'type': 'builtin', 
            'unit': 'Bytes'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Network out guest OS', 
                'locale': 'en-us'
              }
            ], 
            'class': 'network', 
            'counter': 'bytestransmitted', 
            'counterSpecifier': '/builtin/network/bytestransmitted', 
            'type': 'builtin', 
            'unit': 'Bytes'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Network collisions', 
                'locale': 'en-us'
              }
            ], 
            'class': 'network', 
            'counter': 'totalcollisions', 
            'counterSpecifier': '/builtin/network/totalcollisions', 
            'type': 'builtin', 
            'unit': 'Count'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Packets received errors', 
                'locale': 'en-us'
              }
            ], 
            'class': 'network', 
            'counter': 'totalrxerrors', 
            'counterSpecifier': '/builtin/network/totalrxerrors', 
            'type': 'builtin', 
            'unit': 'Count'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Packets sent', 
                'locale': 'en-us'
              }
            ], 
            'class': 'network', 
            'counter': 'packetstransmitted', 
            'counterSpecifier': '/builtin/network/packetstransmitted', 
            'type': 'builtin', 
            'unit': 'Count'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Packets received', 
                'locale': 'en-us'
              }
            ], 
            'class': 'network', 
            'counter': 'packetsreceived', 
            'counterSpecifier': '/builtin/network/packetsreceived', 
            'type': 'builtin', 
            'unit': 'Count'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Packets sent errors', 
                'locale': 'en-us'
              }
            ], 
            'class': 'network', 
            'counter': 'totaltxerrors', 
            'counterSpecifier': '/builtin/network/totaltxerrors', 
            'type': 'builtin', 
            'unit': 'Count'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem transfers/sec', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'transferspersecond', 
            'counterSpecifier': '/builtin/filesystem/transferspersecond', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem % free space', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentfreespace', 
            'counterSpecifier': '/builtin/filesystem/percentfreespace', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem % used space', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentusedspace', 
            'counterSpecifier': '/builtin/filesystem/percentusedspace', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem used space', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'usedspace', 
            'counterSpecifier': '/builtin/filesystem/usedspace', 
            'type': 'builtin', 
            'unit': 'Bytes'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem read bytes/sec', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'bytesreadpersecond', 
            'counterSpecifier': '/builtin/filesystem/bytesreadpersecond', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem free space', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'freespace', 
            'counterSpecifier': '/builtin/filesystem/freespace', 
            'type': 'builtin', 
            'unit': 'Bytes'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem % free inodes', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentfreeinodes', 
            'counterSpecifier': '/builtin/filesystem/percentfreeinodes', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem bytes/sec', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'bytespersecond', 
            'counterSpecifier': '/builtin/filesystem/bytespersecond', 
            'type': 'builtin', 
            'unit': 'BytesPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem reads/sec', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'readspersecond', 
            'counterSpecifier': '/builtin/filesystem/readspersecond', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem write bytes/sec', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'byteswrittenpersecond', 
            'counterSpecifier': '/builtin/filesystem/byteswrittenpersecond', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem writes/sec', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'writespersecond', 
            'counterSpecifier': '/builtin/filesystem/writespersecond', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Filesystem % used inodes', 
                'locale': 'en-us'
              }
            ], 
            'class': 'filesystem', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentusedinodes', 
            'counterSpecifier': '/builtin/filesystem/percentusedinodes', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'CPU IO wait time', 
                'locale': 'en-us'
              }
            ], 
            'class': 'processor', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentiowaittime', 
            'counterSpecifier': '/builtin/processor/percentiowaittime', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'CPU user time', 
                'locale': 'en-us'
              }
            ], 
            'class': 'processor', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentusertime', 
            'counterSpecifier': '/builtin/processor/percentusertime', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'CPU nice time', 
                'locale': 'en-us'
              }
            ], 
            'class': 'processor', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentnicetime', 
            'counterSpecifier': '/builtin/processor/percentnicetime', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'CPU percentage guest OS', 
                'locale': 'en-us'
              }
            ], 
            'class': 'processor', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentprocessortime', 
            'counterSpecifier': '/builtin/processor/percentprocessortime', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'CPU interrupt time', 
                'locale': 'en-us'
              }
            ], 
            'class': 'processor', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentinterrupttime', 
            'counterSpecifier': '/builtin/processor/percentinterrupttime', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'CPU idle time', 
                'locale': 'en-us'
              }
            ], 
            'class': 'processor', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentidletime', 
            'counterSpecifier': '/builtin/processor/percentidletime', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'CPU privileged time', 
                'locale': 'en-us'
              }
            ], 
            'class': 'processor', 
            'condition': 'IsAggregate=TRUE', 
            'counter': 'percentprivilegedtime', 
            'counterSpecifier': '/builtin/processor/percentprivilegedtime', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Memory available', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'availablememory', 
            'counterSpecifier': '/builtin/memory/availablememory', 
            'type': 'builtin', 
            'unit': 'Bytes'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Swap percent used', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'percentusedswap', 
            'counterSpecifier': '/builtin/memory/percentusedswap', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Memory used', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'usedmemory', 
            'counterSpecifier': '/builtin/memory/usedmemory', 
            'type': 'builtin', 
            'unit': 'Bytes'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Page reads', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'pagesreadpersec', 
            'counterSpecifier': '/builtin/memory/pagesreadpersec', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Swap available', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'availableswap', 
            'counterSpecifier': '/builtin/memory/availableswap', 
            'type': 'builtin', 
            'unit': 'Bytes'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Swap percent available', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'percentavailableswap', 
            'counterSpecifier': '/builtin/memory/percentavailableswap', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Mem. percent available', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'percentavailablememory', 
            'counterSpecifier': '/builtin/memory/percentavailablememory', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Pages', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'pagespersec', 
            'counterSpecifier': '/builtin/memory/pagespersec', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Swap used', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'usedswap', 
            'counterSpecifier': '/builtin/memory/usedswap', 
            'type': 'builtin', 
            'unit': 'Bytes'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Memory percentage', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'percentusedmemory', 
            'counterSpecifier': '/builtin/memory/percentusedmemory', 
            'type': 'builtin', 
            'unit': 'Percent'
          }, 
          {
            'annotation': [
              {
                'displayName': 'Page writes', 
                'locale': 'en-us'
              }
            ], 
            'class': 'memory', 
            'counter': 'pageswrittenpersec', 
            'counterSpecifier': '/builtin/memory/pageswrittenpersec', 
            'type': 'builtin', 
            'unit': 'CountPerSecond'
          }
        ]
      }, 
      'syslogEvents': {
        'syslogEventConfiguration': {
          'LOG_AUTH': 'LOG_DEBUG', 
          'LOG_AUTHPRIV': 'LOG_DEBUG', 
          'LOG_CRON': 'LOG_DEBUG', 
          'LOG_DAEMON': 'LOG_DEBUG', 
          'LOG_FTP': 'LOG_DEBUG', 
          'LOG_KERN': 'LOG_DEBUG', 
          'LOG_LOCAL0': 'LOG_DEBUG', 
          'LOG_LOCAL1': 'LOG_DEBUG', 
          'LOG_LOCAL2': 'LOG_DEBUG', 
          'LOG_LOCAL3': 'LOG_DEBUG', 
          'LOG_LOCAL4': 'LOG_DEBUG', 
          'LOG_LOCAL5': 'LOG_DEBUG', 
          'LOG_LOCAL6': 'LOG_DEBUG', 
          'LOG_LOCAL7': 'LOG_DEBUG', 
          'LOG_LPR': 'LOG_DEBUG', 
          'LOG_MAIL': 'LOG_DEBUG', 
          'LOG_NEWS': 'LOG_DEBUG', 
          'LOG_SYSLOG': 'LOG_DEBUG', 
          'LOG_USER': 'LOG_DEBUG', 
          'LOG_UUCP': 'LOG_DEBUG'
        }
      }
    }, 
    'sampleRateInSeconds': 15
  }
}"

			#Replaces the default config with the storage account and VM resource ID in the public settings information
			$publicSettings = $publicSettings.Replace('__DIAGNOSTIC_STORAGE_ACCOUNT__',$storageAccountName)
			$publicSettings = $publicSettings.Replace('__VM_RESOURCE_ID__',$vm.Id)

			# Build the protected settings (storage account SAS token)
			$protectedSettings = "{'storageAccountName': '$storageAccountName','storageAccountSasToken': '$sasToken'}"

			#Finally tell Azure to install and enable the extension
			Set-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $vm.Name -Location $vm.Location -ExtensionType LinuxDiagnostic -Publisher Microsoft.Azure.Diagnostics -Name LinuxDiagnostic -SettingString $publicSettings -ProtectedSettingString $protectedSettings -TypeHandlerVersion 3.0 -AsJob

			#Cleans up variables to save on socket limitation
			Remove-Variable linuxExtensionCheck -Force -Confirm:$false
			Remove-Variable windowsExtensionCheck -Force -Confirm:$false
			Remove-Variable status -Force -Confirm:$false
			Remove-Variable vm -Force -Confirm:$false
			[System.GC]::GetTotalMemory($true) | Out-Null

			#Starts cleanup to allow connections to close
			Start-Sleep -s 10
		}
	}



#Checks for running Jobs
$runningJobs = Get-Job
do {
	if ($runningJobs.state -contains "Running") {
		{ "Jobs Still Running" }
		$runningJobs = Get-Job | Where-Object -Property State -EQ running
		Start-Sleep -Seconds 60
	}
}
until ($runningJobs.state -notcontains "running")

#Remove templates
Remove-Item -Path C:\diag -Recurse -Force

#Displays Jobs and status
Get-Job
