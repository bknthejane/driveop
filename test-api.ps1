# DriveOp API smoke test  (Windows PowerShell 5.1 compatible)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\test-api.ps1
#
# Creates two municipalities with supervisors, mechanics, drivers and vehicles,
# then exercises Vehicles, Drivers, Incidents and JobCards and asserts the
# status codes and the resulting domain state.
#
# Municipalities, supervisors and mechanics go in via sqlcmd because those
# endpoints do not exist yet.

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

function Invoke-Sql {
    param([string]$Query)
    return sqlcmd -S $SqlServer -d $Database -h -1 -W -Q $Query
}

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

Write-Section "Setting up municipalities, supervisors and mechanics"

$stamp = Get-Date -Format "HHmmss"
$codeA = "TA$stamp"
$codeB = "TB$stamp"

$municipalityInsert = "SET NOCOUNT ON; " +
    "INSERT INTO Municipalities (Id, Name, Code, Province, CreatedAt, IsDeleted) VALUES " +
    "(NEWID(), 'Test Municipality A $stamp', '$codeA', 'Gauteng', GETUTCDATE(), 0), " +
    "(NEWID(), 'Test Municipality B $stamp', '$codeB', 'Gauteng', GETUTCDATE(), 0); " +
    "SELECT CONVERT(varchar(36), Id) FROM Municipalities WHERE Code IN ('$codeA','$codeB') ORDER BY Code;"

$sqlOutput = Invoke-Sql $municipalityInsert
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

# Supervisors and mechanics, needed for job card assignment.
$staffInsert = "SET NOCOUNT ON; " +
    "DECLARE @supA uniqueidentifier = NEWID(), @supB uniqueidentifier = NEWID(); " +
    "INSERT INTO Supervisors (Id, Name, Surname, Email, MunicipalityId, CreatedAt, IsDeleted) VALUES " +
    "(@supA, 'Thandi', 'SupA$stamp', 'a@test.gov.za', '$municipalityA', GETUTCDATE(), 0), " +
    "(@supB, 'Sipho', 'SupB$stamp', 'b@test.gov.za', '$municipalityB', GETUTCDATE(), 0); " +
    "INSERT INTO Mechanics (Id, Name, Surname, MunicipalityId, SupervisorId, CreatedAt, IsDeleted) VALUES " +
    "(NEWID(), 'Lerato', 'MechA$stamp', '$municipalityA', @supA, GETUTCDATE(), 0), " +
    "(NEWID(), 'Bongani', 'MechB$stamp', '$municipalityB', @supB, GETUTCDATE(), 0); " +
    "SELECT CONVERT(varchar(36), @supA); SELECT CONVERT(varchar(36), @supB);"

$staffOutput = Invoke-Sql $staffInsert
$staffIds = @($staffOutput | Where-Object { $_ -match '^[0-9a-fA-F]{8}-' })

$supervisorA = $null
$supervisorB = $null
if ($staffIds.Count -ge 2) {
    $supervisorA = $staffIds[0].Trim()
    $supervisorB = $staffIds[1].Trim()
    Write-Host "  Supervisor A: $supervisorA"
    Write-Host "  Supervisor B: $supervisorB"
}
else {
    Write-Host "  Could not create supervisors; assignment tests will be skipped." -ForegroundColor Yellow
}

$mechanicOutput = Invoke-Sql ("SET NOCOUNT ON; SELECT CONVERT(varchar(36), Id) FROM Mechanics WHERE MunicipalityId = '$municipalityA';")
$mechanicIds = @($mechanicOutput | Where-Object { $_ -match '^[0-9a-fA-F]{8}-' })
$mechanicA = if ($mechanicIds.Count -ge 1) { $mechanicIds[0].Trim() } else { $null }

$nextYear = (Get-Date).AddYears(1).ToString("yyyy-MM-dd")
$twoYears = (Get-Date).AddYears(2).ToString("yyyy-MM-dd")

# JobCardService builds the prefix from DateTime.UtcNow, so use UTC here too.
# Local time is ahead of UTC in SAST, so between midnight and 02:00 the local
# date would be a day ahead and the assertion would look for the wrong prefix.
$today = (Get-Date).ToUniversalTime().ToString("yyyyMMdd")
$expectedFirst = "JC-$today-001"

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
$vehicleBId = $vehicleB.Body.id

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

$badStatus = Invoke-Api -Method POST -Path "/api/vehicles" -Body @{
    fleetNumber        = "0003"
    registrationNumber = "$codeA 005-GP"
    make               = "Toyota"
    model              = "Quantum"
    licenseExpiry      = $nextYear
    status             = 999
    municipalityId     = $municipalityA
}
Assert-Status "undefined vehicle status rejected" 400 $badStatus.Status $badStatus.Body

$updated = Invoke-Api -Method PUT -Path "/api/vehicles/$vehicleAId" -Body @{
    registrationNumber = "$codeA 001-GP"
    make               = "Toyota"
    model              = "Hilux Legend"
    licenseExpiry      = $twoYears
    status             = 1
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

$incidentA = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description  = "Engine overheating on the N1 near Midrand."
    incidentType = 1
    vehicleId    = $vehicleAId
    driverId     = $driverAId
}
Assert-Status "log incident in A" 201 $incidentA.Status $incidentA.Body
$incidentAId = $incidentA.Body.id

Assert-True "incident status set server-side to Reported" `
    ($incidentA.Body.status -eq "Reported" -or $incidentA.Body.status -eq 1) `
    "status was '$($incidentA.Body.status)'"

Assert-True "hasJobCard false on a new incident" `
    ($incidentA.Body.hasJobCard -eq $false) `
    "hasJobCard was '$($incidentA.Body.hasJobCard)'"

$incidentB = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description  = "Brake failure reported by the driver."
    incidentType = 1
    vehicleId    = $vehicleBId
    driverId     = $driverBId
}
Assert-Status "log incident in B" 201 $incidentB.Status $incidentB.Body
$incidentBId = $incidentB.Body.id

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

$badEnum = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description  = "Undefined incident type."
    incidentType = 999
    vehicleId    = $vehicleAId
    driverId     = $driverAId
}
Assert-Status "undefined incident type rejected" 400 $badEnum.Status $badEnum.Body

$incidentFilter = "/api/incidents?vehicleId=" + $vehicleAId + "&pageSize=5"
$filtered = Invoke-Api -Method GET -Path $incidentFilter
Assert-Status "filter incidents by vehicle" 200 $filtered.Status $filtered.Body

# ---------------------------------------------------------------- job cards

Write-Section "JobCard generation and the transaction"

$badPriority = Invoke-Api -Method POST -Path "/api/incidents/$incidentAId/jobcards" -Body @{
    priority = 999
    notes    = "Undefined priority."
}
Assert-Status "undefined priority rejected" 400 $badPriority.Status $badPriority.Body

$unknownIncident = Invoke-Api -Method POST -Path ("/api/incidents/" + (NewId) + "/jobcards") -Body @{
    priority = 2
}
Assert-Status "job card for unknown incident" 404 $unknownIncident.Status $unknownIncident.Body

if ($supervisorB) {
    $crossSupervisor = Invoke-Api -Method POST -Path "/api/incidents/$incidentAId/jobcards" -Body @{
        priority             = 2
        assignedSupervisorId = $supervisorB
    }
    Assert-Status "supervisor from another municipality rejected" 400 $crossSupervisor.Status $crossSupervisor.Body
}

$jobCardBody = @{
    priority = 3
    notes    = "Coolant leak suspected. Needs a full inspection."
}
if ($supervisorA) { $jobCardBody.assignedSupervisorId = $supervisorA }
if ($mechanicA)   { $jobCardBody.assignedMechanicId = $mechanicA }

$jobCardA = Invoke-Api -Method POST -Path "/api/incidents/$incidentAId/jobcards" -Body $jobCardBody
Assert-Status "create job card from incident in A" 201 $jobCardA.Status $jobCardA.Body
$jobCardAId = $jobCardA.Body.id

Assert-True "job card number is $expectedFirst for A" `
    ($jobCardA.Body.jobCardNumber -eq $expectedFirst) `
    "number was '$($jobCardA.Body.jobCardNumber)'"

Assert-True "job card status is Open" `
    ($jobCardA.Body.status -eq "Open" -or $jobCardA.Body.status -eq 1) `
    "status was '$($jobCardA.Body.status)'"

# All three writes must have landed.
Assert-True "transaction: incident advanced to JobCardCreated" `
    ($jobCardA.Body.incidentStatus -eq "JobCardCreated" -or $jobCardA.Body.incidentStatus -eq 3) `
    "incidentStatus was '$($jobCardA.Body.incidentStatus)'"

Assert-True "transaction: vehicle advanced to UnderRepair" `
    ($jobCardA.Body.vehicleStatus -eq "UnderRepair" -or $jobCardA.Body.vehicleStatus -eq 2) `
    "vehicleStatus was '$($jobCardA.Body.vehicleStatus)'"

# Confirm independently, not just from the create response.
$vehicleAfter = Invoke-Api -Method GET -Path "/api/vehicles/$vehicleAId"
Assert-True "vehicle status persisted as UnderRepair" `
    ($vehicleAfter.Body.status -eq "UnderRepair" -or $vehicleAfter.Body.status -eq 2) `
    "status was '$($vehicleAfter.Body.status)'"

$incidentAfter = Invoke-Api -Method GET -Path "/api/incidents/$incidentAId"
Assert-True "incident hasJobCard now true" `
    ($incidentAfter.Body.hasJobCard -eq $true) `
    "hasJobCard was '$($incidentAfter.Body.hasJobCard)'"

$duplicateJobCard = Invoke-Api -Method POST -Path "/api/incidents/$incidentAId/jobcards" -Body @{
    priority = 1
}
Assert-Status "second job card on the same incident rejected" 409 $duplicateJobCard.Status $duplicateJobCard.Body

$readJobCard = Invoke-Api -Method GET -Path "/api/jobcards/$jobCardAId"
Assert-Status "read job card by id" 200 $readJobCard.Status $readJobCard.Body

Assert-True "job card carries municipality name" `
    (-not [string]::IsNullOrWhiteSpace($readJobCard.Body.municipalityName)) `
    "municipalityName was '$($readJobCard.Body.municipalityName)'"

# Per-tenant numbering: B counts from 001 as well, on the same day.
$jobCardB = Invoke-Api -Method POST -Path "/api/incidents/$incidentBId/jobcards" -Body @{
    priority = 2
    notes    = "Brake pads to be replaced."
}
Assert-Status "create job card from incident in B" 201 $jobCardB.Status $jobCardB.Body

Assert-True "job card number restarts at $expectedFirst for B" `
    ($jobCardB.Body.jobCardNumber -eq $expectedFirst) `
    "number was '$($jobCardB.Body.jobCardNumber)'"

$missingJobCard = Invoke-Api -Method GET -Path ("/api/jobcards/" + (NewId))
Assert-Status "unknown job card id" 404 $missingJobCard.Status $missingJobCard.Body

# Incident delete must be blocked while a job card exists.
$blockedIncident = Invoke-Api -Method DELETE -Path "/api/incidents/$incidentAId"
Assert-Status "incident with a job card cannot be deleted" 409 $blockedIncident.Status $blockedIncident.Body

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

$hugePage = Invoke-Api -Method GET -Path "/api/vehicles?page=21474838&pageSize=100"
Assert-Status "huge page number does not overflow" 200 $hugePage.Status $hugePage.Body

$negativePage = Invoke-Api -Method GET -Path "/api/vehicles?page=-5&pageSize=10"
Assert-Status "negative page clamped" 200 $negativePage.Status $negativePage.Body

# ---------------------------------------------------------------- soft delete

Write-Section "Soft delete and fleet number reuse"

# Vehicle B is untouched by job cards, so use it for the delete path.
$unassignB = Invoke-Api -Method PUT -Path "/api/vehicles/$vehicleBId" -Body @{
    registrationNumber = "$codeB 001-GP"
    make               = "Isuzu"
    model              = "D-Max"
    licenseExpiry      = $twoYears
    status             = 1
    assignedDriverId   = $null
}
Assert-Status "unassign driver from vehicle B" 204 $unassignB.Status $unassignB.Body

$deleteVehicleB = Invoke-Api -Method DELETE -Path "/api/vehicles/$vehicleBId"
Assert-Status "delete vehicle B" 204 $deleteVehicleB.Status $deleteVehicleB.Body

$goneB = Invoke-Api -Method GET -Path "/api/vehicles/$vehicleBId"
Assert-Status "deleted vehicle hidden by query filter" 404 $goneB.Status $goneB.Body

$rowOutput = Invoke-Sql "SET NOCOUNT ON; SELECT CAST(IsDeleted AS int) FROM Vehicles WHERE Id = '$vehicleBId';"
$flagLine = @($rowOutput | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1)

Assert-True "row still present with IsDeleted = 1" `
    ((($flagLine -join "").Trim()) -eq "1") `
    "sqlcmd returned '$($rowOutput -join ' | ')'"

$reuse = Invoke-Api -Method POST -Path "/api/vehicles" -Body @{
    fleetNumber        = "0001"
    registrationNumber = "$codeB 004-GP"
    make               = "Hino"
    model              = "300"
    licenseExpiry      = $nextYear
    status             = 1
    municipalityId     = $municipalityB
}
Assert-Status "fleet number reusable after soft delete" 201 $reuse.Status $reuse.Body

$nowDeletable = Invoke-Api -Method DELETE -Path "/api/drivers/$driverBId"
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
Write-Host "Expected first job card number: $expectedFirst" -ForegroundColor DarkGray
Write-Host "Reset the database with:" -ForegroundColor DarkGray
Write-Host "  dotnet ef database drop --project DriveOp.Api --force" -ForegroundColor DarkGray
Write-Host "  dotnet ef database update --project DriveOp.Api" -ForegroundColor DarkGray

if ($script:Failed -gt 0) { exit 1 }
