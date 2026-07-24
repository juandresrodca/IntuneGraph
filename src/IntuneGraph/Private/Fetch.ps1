# Fetchers: one per Graph collection. Each returns raw Graph objects (with
# assignments expanded where applicable). API version per endpoint matters:
# Settings Catalog, scripts, remediations and filters live on beta.

function Get-IgRawConfigurationPolicies {
    Invoke-IgRequest -Path '/deviceManagement/configurationPolicies?$expand=assignments' -Api beta
}
function Get-IgRawDeviceConfigurations {
    Invoke-IgRequest -Path '/deviceManagement/deviceConfigurations?$expand=assignments' -Api v1.0
}
function Get-IgRawCompliancePolicies {
    Invoke-IgRequest -Path '/deviceManagement/deviceCompliancePolicies?$expand=assignments' -Api v1.0
}
function Get-IgRawMobileApps {
    Invoke-IgRequest -Path '/deviceAppManagement/mobileApps?$expand=assignments' -Api v1.0
}
function Get-IgRawPlatformScripts {
    Invoke-IgRequest -Path '/deviceManagement/deviceManagementScripts?$expand=assignments' -Api beta
}
function Get-IgRawRemediationScripts {
    Invoke-IgRequest -Path '/deviceManagement/deviceHealthScripts?$expand=assignments' -Api beta
}
function Get-IgRawAssignmentFilters {
    Invoke-IgRequest -Path '/deviceManagement/assignmentFilters' -Api beta
}
function Get-IgRawGroups {
    Invoke-IgRequest -Path '/groups?$select=id,displayName,securityEnabled,groupTypes,membershipRule,mailEnabled' -Api v1.0
}
function Get-IgRawGroupMembers {
    param([Parameter(Mandatory)][string]$GroupId)
    Invoke-IgRequest -Path "/groups/$GroupId/members?`$select=id,displayName,userPrincipalName,deviceId,operatingSystem" -Api v1.0
}
function Get-IgRawManagedDevices {
    Invoke-IgRequest -Path '/deviceManagement/managedDevices?$select=id,deviceName,azureADDeviceId,operatingSystem,userPrincipalName,complianceState,lastSyncDateTime' -Api v1.0
}
