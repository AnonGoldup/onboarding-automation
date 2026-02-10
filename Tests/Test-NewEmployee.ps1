<#
.SYNOPSIS
    Pester tests validating onboarding created all expected objects.

.DESCRIPTION
    After running New-Employee.ps1, these tests verify:
    - AD account exists and is enabled
    - Group memberships match the role template
    - Home folder exists with correct permissions
    - M365 license is assigned

.EXAMPLE
    Invoke-Pester -Path .\Tests\Test-NewEmployee.ps1 -Container (New-PesterContainer -Data @{ Username = 'jsmith'; Department = 'Engineering' })
#>

param(
    [Parameter(Mandatory)]
    [string]$Username,

    [Parameter(Mandatory)]
    [string]$Department
)

Describe "Onboarding Validation for $Username" {

    BeforeAll {
        $templatePath = Join-Path $PSScriptRoot "..\RoleTemplates\RoleTemplate-$Department.json"
        $template = Get-Content $templatePath -Raw | ConvertFrom-Json
        $config = Get-Content (Join-Path $PSScriptRoot "..\Config\config.json") -Raw | ConvertFrom-Json
        $user = Get-ADUser -Identity $Username -Properties MemberOf, HomeDirectory, EmailAddress, Enabled, Department
    }

    Context "Active Directory Account" {
        It "AD account should exist" {
            $user | Should -Not -BeNullOrEmpty
        }

        It "Account should be enabled" {
            $user.Enabled | Should -Be $true
        }

        It "Department should be set to $Department" {
            $user.Department | Should -Be $Department
        }

        It "Email address should be set" {
            $user.EmailAddress | Should -Not -BeNullOrEmpty
        }
    }

    Context "Group Memberships" {
        foreach ($group in $template.ADGroups) {
            It "Should be a member of $group" {
                $members = Get-ADGroupMember -Identity $group | Select-Object -ExpandProperty SamAccountName
                $members | Should -Contain $Username
            }
        }
    }

    Context "Home Folder" {
        It "Home directory path should be set in AD" {
            $user.HomeDirectory | Should -Not -BeNullOrEmpty
        }

        It "Home folder should exist on disk" {
            Test-Path $user.HomeDirectory | Should -Be $true
        }

        It "User should have Modify access to home folder" {
            $acl = Get-Acl $user.HomeDirectory
            $userAccess = $acl.Access | Where-Object {
                $_.IdentityReference -match $Username -and $_.FileSystemRights -match 'Modify'
            }
            $userAccess | Should -Not -BeNullOrEmpty
        }
    }

    Context "Microsoft 365" {
        It "M365 license should be assigned" {
            $mgUser = Get-MgUser -Filter "userPrincipalName eq '$($user.UserPrincipalName)'" -ErrorAction SilentlyContinue
            if ($mgUser) {
                $licenses = Get-MgUserLicenseDetail -UserId $mgUser.Id
                $licenses.SkuId | Should -Contain $template.M365License
            } else {
                Set-ItResult -Skipped -Because "Azure AD sync may not have completed"
            }
        }
    }
}
