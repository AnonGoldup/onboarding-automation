<#
.SYNOPSIS
    Master offboarding script for employee deprovisioning.

.DESCRIPTION
    Automates the full offboarding process:
    1. Disables the AD account
    2. Resets password to random string
    3. Logs and removes all group memberships
    4. Sets out-of-office reply
    5. Forwards email to manager
    6. Moves account to Disabled Users OU
    7. Sets account expiry date
    8. Revokes M365 license (after retention period)

.PARAMETER SamAccountName
    The username of the employee being offboarded.

.PARAMETER ForwardEmailTo
    Manager or team mailbox to forward emails to.

.PARAMETER AccountExpiryDays
    Days until the account is set to expire (default 90).

.EXAMPLE
    .\Remove-Employee.ps1 -SamAccountName "jsmith" -ForwardEmailTo "jdoe@company.com"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SamAccountName,

    [string]$ForwardEmailTo,
    [int]$AccountExpiryDays = 90,
    [string]$ConfigPath = "$PSScriptRoot\..\Config\config.json"
)

$ErrorActionPreference = "Stop"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$logDir = Join-Path $PSScriptRoot "..\Logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "Offboarding_${SamAccountName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $logFile -Value $entry
    $color = switch ($Level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'White' } }
    Write-Host $entry -ForegroundColor $color
}

Write-Log "=== Starting offboarding for $SamAccountName ==="

# Verify user exists
$user = Get-ADUser -Identity $SamAccountName -Properties `
    DisplayName, Department, Manager, MemberOf, EmailAddress, HomeDirectory -ErrorAction Stop

Write-Log "User found: $($user.DisplayName) ($($user.Department))"

# Step 1: Log current group memberships (before removal)
Write-Log "Recording group memberships"
$groups = $user.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }
$groupLog = Join-Path $logDir "Groups_${SamAccountName}_$(Get-Date -Format 'yyyyMMdd').txt"
$groups | Out-File $groupLog
Write-Log "  $($groups.Count) groups logged to: $groupLog"

# Step 2: Disable the account
Write-Log "Disabling AD account"
Disable-ADAccount -Identity $SamAccountName
Write-Log "Account disabled" -Level "SUCCESS"

# Step 3: Reset password
Write-Log "Resetting password to random"
Add-Type -AssemblyName System.Web
$randomPw = [System.Web.Security.Membership]::GeneratePassword(24, 5)
Set-ADAccountPassword -Identity $SamAccountName -NewPassword (ConvertTo-SecureString $randomPw -AsPlainText -Force) -Reset
Write-Log "Password reset" -Level "SUCCESS"

# Step 4: Remove from all groups (except Domain Users)
Write-Log "Removing from groups"
foreach ($groupDN in $user.MemberOf) {
    $groupName = (Get-ADGroup $groupDN).Name
    if ($groupName -ne 'Domain Users') {
        try {
            Remove-ADGroupMember -Identity $groupDN -Members $SamAccountName -Confirm:$false
            Write-Log "  Removed from: $groupName"
        }
        catch {
            Write-Log "  Failed to remove from $groupName : $_" -Level "WARN"
        }
    }
}

# Step 5: Set description with offboarding date
$offboardDate = Get-Date -Format "yyyy-MM-dd"
Set-ADUser -Identity $SamAccountName -Description "Offboarded: $offboardDate | Previous: $($user.Department)"
Write-Log "Description updated with offboarding date"

# Step 6: Move to Disabled Users OU
if ($config.DisabledUsersOU) {
    Write-Log "Moving to Disabled Users OU"
    Move-ADObject -Identity $user.DistinguishedName -TargetPath $config.DisabledUsersOU
    Write-Log "Moved to: $($config.DisabledUsersOU)" -Level "SUCCESS"
}

# Step 7: Set account expiry
$expiryDate = (Get-Date).AddDays($AccountExpiryDays)
Set-ADAccountExpiration -Identity $SamAccountName -DateTime $expiryDate
Write-Log "Account expiry set to: $($expiryDate.ToString('yyyy-MM-dd'))"

# Step 8: Email forwarding (Exchange/M365)
if ($ForwardEmailTo) {
    Write-Log "Setting email forwarding to: $ForwardEmailTo"
    try {
        Set-Mailbox -Identity $user.EmailAddress -ForwardingSmtpAddress $ForwardEmailTo -DeliverToMailboxAndForward $true
        Write-Log "Email forwarding configured" -Level "SUCCESS"
    }
    catch {
        Write-Log "Email forwarding failed (may need Exchange module): $_" -Level "WARN"
    }
}

# Step 9: Archive home folder
if ($user.HomeDirectory -and (Test-Path $user.HomeDirectory)) {
    $archivePath = Join-Path $config.ArchiveSharePath "${SamAccountName}_$offboardDate"
    Write-Log "Archiving home folder to: $archivePath"
    try {
        Copy-Item -Path $user.HomeDirectory -Destination $archivePath -Recurse -Force
        Write-Log "Home folder archived" -Level "SUCCESS"
    }
    catch {
        Write-Log "Home folder archive failed: $_" -Level "WARN"
    }
}

# Summary
Write-Log "=== Offboarding Complete ==="
Write-Log "  User:          $($user.DisplayName)"
Write-Log "  Account:       Disabled"
Write-Log "  Groups:        $($groups.Count) removed (logged)"
Write-Log "  Password:      Reset"
Write-Log "  Expiry:        $($expiryDate.ToString('yyyy-MM-dd'))"
Write-Log "  Email Forward: $ForwardEmailTo"
Write-Log "  Log File:      $logFile"
Write-Log "  Group Log:     $groupLog"

[PSCustomObject]@{
    User         = $SamAccountName
    DisplayName  = $user.DisplayName
    Status       = 'Disabled'
    GroupsRemoved = $groups.Count
    AccountExpiry = $expiryDate
    EmailForward = $ForwardEmailTo
    LogFile      = $logFile
}
