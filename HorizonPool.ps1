<#
.SYNOPSIS
Horizon Pool monitor sensor for PRTG

.DESCRIPTION
Scans specified target pool for number of sessions and hosts available in Horizon Connection Server.
Reports back to PRTG as load in percentages and counts for Horizon Pool monitoring.

Requires installation of VMware.PowerCLI and VMware.Hv.Helper PowerShell modules

.PARAMETER hvServer
Hostname of the Horizon Connection Server.

.PARAMETER username
Username to login to Horizon Connection Server. Specify AD credentials with format: domain\username.

.PARAMETER password
Password for specified username.

.PARAMETER poolId
Name of the Horizon Pool to gather data about.

.EXAMPLE
HorizonPool.ps1 -hvServer connection.server.com -username domain\username -password password -poolId Pool-Name
#>

Param(
[string]$hvServer = "host",
[string]$username = "Administrator",
[string]$password = "password",
[string]$poolId = "poolid"
)

# Create secure credential
$secPassword = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential ($username, $secPassword)

# Open connection to hvServer, assigned to variable to suppress output
$hvConn = Connect-HVServer -Server $hvServer -Credential $cred

# Gather data about poolId
$poolSummary = (Get-HVPoolSummary -PoolName $poolId).DesktopSummaryData | select NumSessions,NumMachines
$farmSummary = Get-HVFarmSummary | where {$_.Data.DesktopName -eq $poolId}

$hvExtData = $Global:DefaultHVServers.ExtensionData
$farmHealth = New-Object VMware.Hv.FarmHealthService
$checkFarmHealth = $farmHealth.FarmHealth_Get($hvExtData, $farmSummary.Id)

# Calculate sums and percentages before reporting to PRTG
$numAvailHosts = ($CheckFarmHealth.RdsServerHealth | where Status -eq "AVAILABLE").Count
$pctAvailHosts = [math]::round(($numAvailHosts / $poolSummary.NumMachines) * 100,2)
$pctSessions = [math]::round(($poolSummary.NumSessions / ($farmSummary.Data).MaximumNumberOfSessions) * 100,2)

# Format return data as PRTG XML standard format
$return = @"
<prtg>
    <result>
    <channel>Session Load</channel>
    <unit>Percent</unit>
    <float>1</float>
    <LimitMaxWarning>85</LimitMaxWarning>
    <LimitMaxError>95</LimitMaxError>
    <LimitMode>1</LimitMode>
    <value>$pctSessions</value>
    </result>
    <result>
    <channel>Host Availability</channel>
    <unit>Percent</unit>
    <float>1</float>
    <LimitMinWarning>95</LimitMinWarning>
    <LimitMinError>75</LimitMinError>
    <LimitMode>1</LimitMode>
    <value>$pctAvailHosts</value>
    </result>
    <result>
    <channel>Hosts Available</channel>
    <value>$numAvailHosts</value>
    </result>
    <result>
    <channel>Session Count</channel>
    <value>$($poolSummary.NumSessions)</value>
    </result>
</prtg>
"@

# Close hvServer connection and output result
Disconnect-HVServer -Confirm:$false
$return
