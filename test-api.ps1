# DriveOp API smoke test  (Windows PowerShell 5.1 compatible)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\test-api.ps1
#
# Creates two municipalities with drivers and vehicles, then exercises the
# Vehicles, Drivers and Incidents endpoints and asserts the status codes.
#
# Municipalities go in via sqlcmd because there is no Municipalities endpoint.

param(
    [string]$BaseUrl = "http://localhost:5030",
    [string]$SqlServer = "localhost",
    [string]$Database = "DriveOp"
)

$script:Passed = 0
$script:Failed = 0

# ---------------------------------------------------------------- helpers

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        $Body
    )

    $uri = $BaseUrl + $Path

    try {
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 6
            $response = Invoke-WebRequest -Method $Method -Uri $uri -Body $json `
                -ContentType "application/json" -UseBasicParsing
        }
        else {
            $response = Invoke-WebRequest -Method $Method -Uri $uri -UseBasicParsing
        }

        $parsed = $null
        if ($response.Content) {
            try { $parsed = $response.Content | ConvertFrom-Json } catch { $parsed = $null }
        }

        return @{ Status = [int]$response.StatusCode; Body = $parsed }
    }
    catch [System.Net.WebException] {
        $webResponse = $_.Exception.Response

        if ($null -eq $webResponse) {
            Write-Host "  Could not reach $uri" -ForegroundColor Red
            return @{ Status = 0; Body = $null }
        }

        $status = [int]$webResponse.StatusCode
        $parsed = $null

        try {
            $reader = New-Object System.IO.StreamReader($webResponse.GetResponseStream())
            $content = $reader.ReadToEnd()
            $reader.Close()
            if ($content) { $parsed = $content | ConvertFrom-Json }
        }
        catch { $parsed = $null }

        return @{ Status = $status; Body = $parsed }
    }
}

function Assert-Status {
    param(
        [string]$Name,
        [int]$Expected,
        [int]$Actual,
        $Body
    )

    if ($Expected -eq $Actual) {
        Write-Host "  PASS  " -ForegroundColor Green -NoNewline
        Write-Host "$Name  ($Actual)"
        $script:Passed++
    }
    else {
        Write-Host "  FAIL  " -ForegroundColor Red -NoNewline
        Write-Host "$Name  expected $Expected, got $Actual"

        if ($Body) {
            $detail = $null
            if ($Body.PSObject.Properties.Name -contains "detail") { $detail = $Body.detail }
            if (-not $detail -and $Body.PSObject.Properties.Name -contains "title") { $detail = $Body.title }
            if (-not $detail) { $detail = ($Body | ConvertTo-Json -Compress -Depth 4) }
            Write-Host "        $detail" -ForegroundColor DarkGray
        }
        $script:Failed++
    }
}

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Detail
    )

    if ($Condition) {
        Write-Host "  PASS  " -ForegroundColor Green -NoNewline
        Write-Host $Name
        $script:Passed++
    }
    else {
        Write-Host "  FAIL  " -ForegroundColor Red -NoNewline
        Write-Host "$Name  -  $Detail"
        $script:Failed++
    }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
}

function NewId { return [guid]::NewGuid().ToString() }

# ---------------------------------------------------------------- setup

Write-Host "DriveOp API smoke test"
Write-Host $BaseUrl -ForegroundColor DarkGray

$ping = Invoke-Api -Method GET -Path "/api/vehicles"
if ($ping.Status -ne 200) {
    Write-Host ""
    Write-Host "API not reachable (status $($ping.Status))." -ForegroundColor Red
    Write-Host "Start it with: dotnet run --project DriveOp.Api" -ForegroundColor Red
    exit 1
}

Write-Section "Setting up municipalities"

$stamp = Get-Date -Format "HHmmss"
$codeA = "TA$stamp"
$codeB = "TB$stamp"

$insert = "SET NOCOUNT ON; " +
          "INSERT INTO Municipalities (Id, Name, Code, Province, CreatedAt, IsDeleted) VALUES " +
          "(NEWID(), 'Test Municipality A $stamp', '$codeA', 'Gauteng', GETUTCDATE(), 0), " +
          "(NEWID(), 'Test Municipality B $stamp', '$codeB', 'Gauteng', GETUTCDATE(), 0); " +
          "SELECT CONVERT(varchar(36), Id) FROM Municipalities WHERE Code IN ('$codeA','$codeB') ORDER BY Code;"

$sqlOutput = sqlcmd -S $SqlServer -d $Database -h -1 -W -Q $insert
$ids = @($sqlOutput | Where-Object { $_ -match '^[0-9a-fA-F]{8}-' })

if ($ids.Count -lt 2) {
    Write-Host "Could not create municipalities. sqlcmd said:" -ForegroundColor Red
    $sqlOutput | ForEach-Object { Write-Host "  $_" }
    exit 1
}

$municipalityA = $ids[0].Trim()
$municipalityB = $ids[1].Trim()

Write-Host "  A: $municipalityA  ($codeA)"
Write-Host "  B: $municipalityB  ($codeB)"

$nextYear = (Get-Date).AddYears(1).ToString("yyyy-MM-dd")
$twoYears = (Get-Date).AddYears(2).ToString("yyyy-MM-dd")

# ---------------------------------------------------------------- drivers

Write-Section "Drivers"

$driverA = Invoke-Api -Method POST -Path "/api/drivers" -Body @{
    name           = "Thabo"
    surname        = "Mokoena"
    licenseNumber  = "$codeA-DL-001"
    municipalityId = $municipalityA
}
Assert-Status "create driver in A" 201 $driverA.Status $driverA.Body
$driverAId = $driverA.Body.id

$driverB = Invoke-Api -Method POST -Path "/api/drivers" -Body @{
    name           = "Naledi"
    surname        = "Khumalo"
    licenseNumber  = "$codeB-DL-001"
    municipalityId = $municipalityB
}
Assert-Status "create driver in B" 201 $driverB.Status $driverB.Body
$driverBId = $driverB.Body.id

$dupLicence = Invoke-Api -Method POST -Path "/api/drivers" -Body @{
    name           = "Duplicate"
    surname        = "Licence"
    licenseNumber  = "$codeA-DL-001"
    municipalityId = $municipalityB
}
Assert-Status "duplicate licence number rejected" 409 $dupLicence.Status $dupLicence.Body

$badMunicipality = Invoke-Api -Method POST -Path "/api/drivers" -Body @{
    name           = "Orphan"
    surname        = "Driver"
    licenseNumber  = "$codeA-DL-999"
    municipalityId = (NewId)
}
Assert-Status "unknown municipality rejected" 400 $badMunicipality.Status $badMunicipality.Body

$missingDriver = Invoke-Api -Method GET -Path ("/api/drivers/" + (NewId))
Assert-Status "unknown driver id" 404 $missingDriver.Status $missingDriver.Body

$malformedId = Invoke-Api -Method GET -Path "/api/drivers/not-a-guid"
Assert-Status "malformed id caught by route constraint" 404 $malformedId.Status $malformedId.Body

# ---------------------------------------------------------------- vehicles

Write-Section "Vehicles and tenant-scoped fleet numbers"

$vehicleA = Invoke-Api -Method POST -Path "/api/vehicles" -Body @{
    fleetNumber        = "0001"
    registrationNumber = "$codeA 001-GP"
    make               = "Toyota"
    model              = "Hilux"
    licenseExpiry      = $nextYear
    status             = 1
    municipalityId     = $municipalityA
    assignedDriverId   = $driverAId
}
Assert-Status "create vehicle 0001 in A" 201 $vehicleA.Status $vehicleA.Body
$vehicleAId = $vehicleA.Body.id

# The point of the composite index: B may also use 0001.
$vehicleB = Invoke-Api -Method POST -Path "/api/vehicles" -Body @{
    fleetNumber        = "0001"
    registrationNumber = "$codeB 001-GP"
    make               = "Isuzu"
    model              = "D-Max"
    licenseExpiry      = $nextYear
    status             = 1
    municipalityId     = $municipalityB
    assignedDriverId   = $driverBId
}
Assert-Status "same fleet number 0001 allowed in B" 201 $vehicleB.Status $vehicleB.Body

$dupFleet = Invoke-Api -Method POST -Path "/api/vehicles" -Body @{
    fleetNumber        = "0001"
    registrationNumber = "$codeA 002-GP"
    make               = "Ford"
    model              = "Ranger"
    licenseExpiry      = $nextYear
    status             = 1
    municipalityId     = $municipalityA
}
Assert-Status "duplicate fleet number within A rejected" 409 $dupFleet.Status $dupFleet.Body

$crossDriver = Invoke-Api -Method POST -Path "/api/vehicles" -Body @{
    fleetNumber        = "0002"
    registrationNumber = "$codeA 003-GP"
    make               = "Nissan"
    model              = "NP300"
    licenseExpiry      = $nextYear
    status             = 1
    municipalityId     = $municipalityA
    assignedDriverId   = $driverBId
}
Assert-Status "driver from another municipality rejected" 400 $crossDriver.Status $crossDriver.Body

$updated = Invoke-Api -Method PUT -Path "/api/vehicles/$vehicleAId" -Body @{
    registrationNumber = "$codeA 001-GP"
    make               = "Toyota"
    model              = "Hilux Legend"
    licenseExpiry      = $twoYears
    status             = 2
    assignedDriverId   = $driverAId
}
Assert-Status "update vehicle" 204 $updated.Status $updated.Body

$reread = Invoke-Api -Method GET -Path "/api/vehicles/$vehicleAId"
Assert-Status "read updated vehicle" 200 $reread.Status $reread.Body
Assert-True "audit: model changed and updatedAt stamped" `
    ($reread.Body.model -eq "Hilux Legend" -and $null -ne $reread.Body.updatedAt) `
    "model='$($reread.Body.model)' updatedAt='$($reread.Body.updatedAt)'"

# ---------------------------------------------------------------- delete guard

Write-Section "Delete guards"

$blockedDriver = Invoke-Api -Method DELETE -Path "/api/drivers/$driverAId"
Assert-Status "driver with assigned vehicle blocked" 409 $blockedDriver.Status $blockedDriver.Body

# ---------------------------------------------------------------- incidents

Write-Section "Incidents"

$incident = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description  = "Engine overheating on the N1 near Midrand."
    incidentType = 1
    vehicleId    = $vehicleAId
    driverId     = $driverAId
}
Assert-Status "log incident, same municipality" 201 $incident.Status $incident.Body
$incidentId = $incident.Body.id

Assert-True "incident status set server-side to Reported" `
    ($incident.Body.status -eq "Reported" -or $incident.Body.status -eq 1) `
    "status was '$($incident.Body.status)'"

Assert-True "hasJobCard false on a new incident" `
    ($incident.Body.hasJobCard -eq $false) `
    "hasJobCard was '$($incident.Body.hasJobCard)'"

# The rule the database cannot express.
$crossIncident = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description  = "Vehicle from A with driver from B, should be rejected."
    incidentType = 1
    vehicleId    = $vehicleAId
    driverId     = $driverBId
}
Assert-Status "cross-municipality incident rejected" 400 $crossIncident.Status $crossIncident.Body

$unknownVehicle = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description  = "Unknown vehicle."
    incidentType = 1
    vehicleId    = (NewId)
    driverId     = $driverAId
}
Assert-Status "unknown vehicle rejected" 400 $unknownVehicle.Status $unknownVehicle.Body

$emptyDescription = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description  = ""
    incidentType = 1
    vehicleId    = $vehicleAId
    driverId     = $driverAId
}
Assert-Status "empty description rejected by annotations" 400 $emptyDescription.Status $emptyDescription.Body

$incidentFilter = "/api/incidents?vehicleId=" + $vehicleAId + "&pageSize=5"
$filtered = Invoke-Api -Method GET -Path $incidentFilter
Assert-Status "filter incidents by vehicle" 200 $filtered.Status $filtered.Body

# ---------------------------------------------------------------- pagination

Write-Section "Pagination"

$paged = Invoke-Api -Method GET -Path "/api/vehicles?page=1&pageSize=1"
Assert-Status "paged vehicles" 200 $paged.Status $paged.Body

Assert-True "pageSize honoured, totalCount = $($paged.Body.totalCount)" `
    ($paged.Body.items.Count -le 1 -and $paged.Body.totalCount -ge 2) `
    "items=$($paged.Body.items.Count) totalCount=$($paged.Body.totalCount)"

$capped = Invoke-Api -Method GET -Path "/api/vehicles?pageSize=99999"
Assert-True "pageSize capped at $($capped.Body.pageSize)" `
    ($capped.Body.pageSize -le 100) `
    "pageSize was $($capped.Body.pageSize)"

# ---------------------------------------------------------------- soft delete

Write-Section "Soft delete and fleet number reuse"

$deleteIncident = Invoke-Api -Method DELETE -Path "/api/incidents/$incidentId"
Assert-Status "delete incident" 204 $deleteIncident.Status $deleteIncident.Body

$unassign = Invoke-Api -Method PUT -Path "/api/vehicles/$vehicleAId" -Body @{
    registrationNumber = "$codeA 001-GP"
    make               = "Toyota"
    model              = "Hilux Legend"
    licenseExpiry      = $twoYears
    status             = 2
    assignedDriverId   = $null
}
Assert-Status "unassign driver from vehicle" 204 $unassign.Status $unassign.Body

$deleteVehicle = Invoke-Api -Method DELETE -Path "/api/vehicles/$vehicleAId"
Assert-Status "delete vehicle" 204 $deleteVehicle.Status $deleteVehicle.Body

$gone = Invoke-Api -Method GET -Path "/api/vehicles/$vehicleAId"
Assert-Status "deleted vehicle hidden by query filter" 404 $gone.Status $gone.Body

# The row must still be there.
$rowQuery = "SET NOCOUNT ON; SELECT CAST(IsDeleted AS int) FROM Vehicles WHERE Id = '$vehicleAId';"
$rowOutput = sqlcmd -S $SqlServer -d $Database -h -1 -W -Q $rowQuery
$flagLine = @($rowOutput | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1)

Assert-True "row still present with IsDeleted = 1" `
    ((($flagLine -join "").Trim()) -eq "1") `
    "sqlcmd returned '$($rowOutput -join ' | ')'"

# Filtered index should now allow the number again.
$reuse = Invoke-Api -Method POST -Path "/api/vehicles" -Body @{
    fleetNumber        = "0001"
    registrationNumber = "$codeA 004-GP"
    make               = "Hino"
    model              = "300"
    licenseExpiry      = $nextYear
    status             = 1
    municipalityId     = $municipalityA
}
Assert-Status "fleet number reusable after soft delete" 201 $reuse.Status $reuse.Body

$nowDeletable = Invoke-Api -Method DELETE -Path "/api/drivers/$driverAId"
Assert-Status "driver deletable once unassigned" 204 $nowDeletable.Status $nowDeletable.Body

# ---------------------------------------------------------------- summary

Write-Host ""
Write-Host "--------------------------------------------------"
Write-Host "Passed: $script:Passed" -ForegroundColor Green -NoNewline
if ($script:Failed -gt 0) {
    Write-Host "   Failed: $script:Failed" -ForegroundColor Red
}
else {
    Write-Host "   Failed: 0" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Test municipality codes: $codeA, $codeB" -ForegroundColor DarkGray
Write-Host "Reset the database with:" -ForegroundColor DarkGray
Write-Host "  dotnet ef database drop --project DriveOp.Api --force" -ForegroundColor DarkGray
Write-Host "  dotnet ef database update --project DriveOp.Api" -ForegroundColor DarkGray

if ($script:Failed -gt 0) { exit 1 }
