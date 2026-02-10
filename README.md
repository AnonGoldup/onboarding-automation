# Employee Lifecycle Automation

PowerShell-based automation for employee onboarding and offboarding in Active Directory and Microsoft 365 environments. Uses role-based templates for consistent, repeatable provisioning across departments.

## Features

### Onboarding
- AD account creation with department-specific attributes
- Role template-driven group membership assignment
- Home folder provisioning with NTFS permissions
- Microsoft 365 license assignment via Microsoft Graph
- Bulk onboarding from HR CSV exports
- Structured logging with timestamped audit trail

### Offboarding
- Account disable with password reset
- Group membership logging and removal
- Email forwarding to manager or team mailbox
- Home folder archival to network share
- Account expiry scheduling (default 90 days)
- Automated move to Disabled Users OU

### Validation
- Pester test suite for post-onboarding verification
- Validates AD account, group memberships, home folder, and M365 license

## Project Structure

```
onboarding-automation/
├── Onboarding/
│   ├── New-Employee.ps1            # Single employee onboarding
│   └── New-EmployeeFromCSV.ps1     # Bulk onboarding from CSV
├── Offboarding/
│   └── Remove-Employee.ps1         # Employee offboarding
├── RoleTemplates/
│   ├── RoleTemplate-Engineering.json
│   ├── RoleTemplate-Finance.json
│   └── RoleTemplate-Operations.json
├── Config/
│   └── config.example.json         # Environment configuration template
├── Tests/
│   └── Test-NewEmployee.ps1        # Pester validation tests
└── README.md
```

## Role Templates

Each department has a JSON template defining:
- AD security groups
- M365 license SKU
- Teams channels
- SharePoint site access
- Default OU placement
- Home folder share path

| Department | Groups | Key Access |
|-----------|--------|------------|
| Engineering | 6 | GitHub, Dev Resources |
| Finance | 6 | Sage ERP, Power BI |
| Operations | 6 | Fleet Management, Timesheets |

## Usage

### Single Employee Onboarding

```powershell
.\Onboarding\New-Employee.ps1 `
    -FirstName "John" `
    -LastName "Smith" `
    -Department "Engineering" `
    -Title "Developer" `
    -Manager "jdoe" `
    -StartDate "2026-03-01"
```

### Bulk Onboarding from CSV

```powershell
.\Onboarding\New-EmployeeFromCSV.ps1 -CsvPath "C:\HR\NewHires.csv"
```

CSV format: `FirstName, LastName, Department, Title, Manager, StartDate`

### Offboarding

```powershell
.\Offboarding\Remove-Employee.ps1 `
    -SamAccountName "jsmith" `
    -ForwardEmailTo "jdoe@company.com" `
    -AccountExpiryDays 90
```

### Validation Tests

```powershell
Invoke-Pester -Path .\Tests\Test-NewEmployee.ps1 `
    -Container (New-PesterContainer -Data @{
        Username = 'jsmith'
        Department = 'Engineering'
    })
```

## Prerequisites

- Windows Server with RSAT (Active Directory module)
- Microsoft Graph PowerShell SDK (`Microsoft.Graph.Users`, `Microsoft.Graph.Identity.DirectoryManagement`)
- Pester v5+ for validation tests
- Exchange Online Management module (for email forwarding)
- Appropriate AD and M365 admin permissions

## Configuration

Copy `Config/config.example.json` to `Config/config.json` and update with your environment values:
- Domain and email domain
- Organizational Unit paths
- File share paths
- SMTP settings
- M365 tenant and application IDs

## License

MIT License
