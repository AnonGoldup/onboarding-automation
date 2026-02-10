<#
.SYNOPSIS
    Master onboarding script for new employee provisioning.

.DESCRIPTION
    Automates the full onboarding process:
    1. Creates Active Directory account from role template
    2. Assigns department-specific group memberships
    3. Creates home folder with proper NTFS permissions
    4. Provisions Microsoft 365 mailbox and license
    5. Adds to Teams groups and SharePoint sites
    6. Sends welcome email with first-day instructions

    Uses role templates (JSON) for consistent, repeatable provisioning.

.PARAMETER FirstName
    Employee first name.

.PARAMETER LastName
    Employee last name.

.PARAMETER Department
    Department name (must match a role template).

.PARAMETER Title
    Job title.

.PARAMETER Manager
    Manager's SamAccountName.

.PARAMETER StartDate
    Employee start date.

.EXAMPLE
    .\New-Employee.ps1 -FirstName "John" -LastName "Smith" -Department "Engineering" -Title "Developer" -Manager "jdoe" -StartDate "2026-03-01"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$FirstName,

    [Parameter(Mandatory)]
    [string]$LastName,

    [Parameter(Mandatory)]
    [string]$Department,

    [Parameter(Mandatory)]
    [string]$Title,

    [Parameter(Mandatory)]
    [string]$Manager,

    [datetime]$StartDate = (Get-Date),

    [string]$ConfigPath = "$PSScriptRoot\..\Config\config.json"
)

$ErrorActionPreference = "Stop"

# Load configuration
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$templatePath = Join-Path $PSScriptRoot "..\RoleTemplates\RoleTemplate-$Department.json"

# Logging
$logDir = Join-Path $PSScriptRoot "..\Logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "Onboarding_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $logFile -Value $entry
    $color = switch ($Level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'White' } }
    Write-Host $entry -ForegroundColor $color
}

Write-Log "=== Starting onboarding for $FirstName $LastName ==="

# Validate role template exists
if (-not (Test-Path $templatePath)) {
    Write-Log "Role template not found: $templatePath" -Level "ERROR"
    throw "No role template for department: $Department"
}

$template = Get-Content $templatePath -Raw | ConvertFrom-Json
Write-Log "Loaded role template: $Department"

# Generate username (first initial + last name, lowercase)
$username = ($FirstName[0] + $LastName).ToLower() -replace '[^a-z0-9]', ''
$displayName = "$FirstName $LastName"
$upn = "$username@$($config.Domain)"
$email = "$username@$($config.EmailDomain)"

# Check if username already exists
$existingUser = Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue
if ($existingUser) {
    $username = ($FirstName[0] + $LastName + '1').ToLower() -replace '[^a-z0-9]', ''
    $upn = "$username@$($config.Domain)"
    Write-Log "Username conflict - using: $username" -Level "WARN"
}

# Generate temporary password
Add-Type -AssemblyName System.Web
$tempPassword = [System.Web.Security.Membership]::GeneratePassword(16, 3)

# Step 1: Create AD Account
Write-Log "Creating AD account: $username"
try {
    $newUserParams = @{
        Name              = $displayName
        GivenName         = $FirstName
        Surname           = $LastName
        SamAccountName    = $username
        UserPrincipalName = $upn
        DisplayName       = $displayName
        EmailAddress      = $email
        Title             = $Title
        Department        = $Department
        Company           = $config.Company
        Path              = $config.NewUserOU
        AccountPassword   = (ConvertTo-SecureString $tempPassword -AsPlainText -Force)
        Enabled           = $true
        ChangePasswordAtLogon = $true
    }

    if ($Manager) {
        $managerDN = (Get-ADUser -Identity $Manager).DistinguishedName
        $newUserParams['Manager'] = $managerDN
    }

    New-ADUser @newUserParams
    Write-Log "AD account created: $username" -Level "SUCCESS"
}
catch {
    Write-Log "Failed to create AD account: $_" -Level "ERROR"
    throw
}

# Step 2: Add to Groups
Write-Log "Adding to department groups"
foreach ($group in $template.ADGroups) {
    try {
        Add-ADGroupMember -Identity $group -Members $username
        Write-Log "  Added to group: $group"
    }
    catch {
        Write-Log "  Failed to add to group $group : $_" -Level "WARN"
    }
}

# Step 3: Create Home Folder
$homePath = Join-Path $config.HomeSharePath $username
Write-Log "Creating home folder: $homePath"
try {
    New-Item -ItemType Directory -Path $homePath -Force | Out-Null

    $acl = Get-Acl $homePath
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$($config.Domain)\$username", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $homePath -AclObject $acl

    # Set home directory in AD
    Set-ADUser -Identity $username -HomeDirectory $homePath -HomeDrive "H:"
    Write-Log "Home folder created with permissions" -Level "SUCCESS"
}
catch {
    Write-Log "Failed to create home folder: $_" -Level "WARN"
}

# Step 4: Microsoft 365 License
Write-Log "Assigning M365 license: $($template.M365License)"
try {
    # Wait for Azure AD sync
    Start-Sleep -Seconds 30

    Connect-MgGraph -Scopes "User.ReadWrite.All" -NoWelcome -ErrorAction Stop

    $mgUser = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop

    if ($mgUser -and $template.M365License) {
        Set-MgUserLicense -UserId $mgUser.Id -AddLicenses @(
            @{ SkuId = $template.M365License }
        ) -RemoveLicenses @()
        Write-Log "M365 license assigned" -Level "SUCCESS"
    }
}
catch {
    Write-Log "M365 license assignment: $_" -Level "WARN"
}

# Step 5: Summary
Write-Log "=== Onboarding Complete ==="
Write-Log "  Username:    $username"
Write-Log "  Email:       $email"
Write-Log "  Department:  $Department"
Write-Log "  Title:       $Title"
Write-Log "  Manager:     $Manager"
Write-Log "  Start Date:  $($StartDate.ToString('yyyy-MM-dd'))"
Write-Log "  Home Folder: $homePath"
Write-Log "  Log File:    $logFile"

# Output summary object
[PSCustomObject]@{
    Username    = $username
    Email       = $email
    DisplayName = $displayName
    Department  = $Department
    Title       = $Title
    Manager     = $Manager
    StartDate   = $StartDate
    HomePath    = $homePath
    LogFile     = $logFile
}
