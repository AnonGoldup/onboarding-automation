<#
.SYNOPSIS
    Bulk onboarding from HR CSV export.

.DESCRIPTION
    Processes a CSV file containing new hire information and
    runs the New-Employee.ps1 script for each entry.
    CSV must have columns: FirstName, LastName, Department, Title, Manager, StartDate.

.PARAMETER CsvPath
    Path to the CSV file with new hire data.

.EXAMPLE
    .\New-EmployeeFromCSV.ps1 -CsvPath "C:\HR\NewHires_March2026.csv"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CsvPath
)

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found: $CsvPath"
}

$newHires = Import-Csv $CsvPath
Write-Host "Processing $($newHires.Count) new hires from: $CsvPath" -ForegroundColor Cyan

$results = @()
$scriptPath = Join-Path $PSScriptRoot "New-Employee.ps1"

foreach ($hire in $newHires) {
    Write-Host ""
    Write-Host "--- Processing: $($hire.FirstName) $($hire.LastName) ---" -ForegroundColor White

    try {
        $result = & $scriptPath `
            -FirstName $hire.FirstName `
            -LastName $hire.LastName `
            -Department $hire.Department `
            -Title $hire.Title `
            -Manager $hire.Manager `
            -StartDate ([datetime]$hire.StartDate)

        $result | Add-Member -NotePropertyName 'Status' -NotePropertyValue 'Success'
        $results += $result
    }
    catch {
        Write-Host "FAILED: $($hire.FirstName) $($hire.LastName) - $_" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Username    = 'FAILED'
            DisplayName = "$($hire.FirstName) $($hire.LastName)"
            Department  = $hire.Department
            Status      = "Error: $_"
        }
    }
}

# Summary
Write-Host ""
Write-Host "=== Bulk Onboarding Summary ===" -ForegroundColor Green
$success = ($results | Where-Object { $_.Status -eq 'Success' }).Count
$failed = ($results | Where-Object { $_.Status -ne 'Success' }).Count
Write-Host "  Total:   $($results.Count)"
Write-Host "  Success: $success" -ForegroundColor Green
Write-Host "  Failed:  $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'White' })

$results | Format-Table Username, DisplayName, Department, Status -AutoSize
