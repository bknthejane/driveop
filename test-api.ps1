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

# Enums may serialise as names or ints depending on converter config.
function Test-Enum {
    param($Actual, [string]$Name, [int]$Value)
    return ($Actual -eq $Name -or $Actual -eq $Value)
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

$mechanicBOutput = Invoke-Sql ("SET NOCOUNT ON; SELECT CONVERT(varchar(36), Id) FROM Mechanics WHERE MunicipalityId = '$municipalityB';")
$mechanicBIds = @($mechanicBOutput | Where-Object { $_ -match '^[0-9a-fA-F]{8}-' })
$mechanicB = if ($mechanicBIds.Count -ge 1) { $mechanicBIds[0].Trim() } else { $null }

$nextYear = (Get-Date).AddYears(1).ToString("yyyy-MM-dd")
$twoYears = (Get-Date).AddYears(2).ToString("yyyy-MM-dd")

# JobCardService builds the prefix from DateTime.UtcNow, so use UTC here too.
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

# A second vehicle in A, used for the cancellation path.
$vehicleA2 = Invoke-Api -Method POST -Path "/api/vehicles" -Body @{
    fleetNumber        = "0002"
    registrationNumber = "$codeA 002-GP"
    make               = "Ford"
    model              = "Ranger"
    licenseExpiry      = $nextYear
    status             = 1
    municipalityId     = $municipalityA
}
Assert-Status "create second vehicle in A" 201 $vehicleA2.Status $vehicleA2.Body
$vehicleA2Id = $vehicleA2.Body.id

$dupFleet = Invoke-Api -Method POST -Path "/api/vehicles" -Body @{
    fleetNumber        = "0001"
    registrationNumber = "$codeA 009-GP"
    make               = "Ford"
    model              = "Ranger"
    licenseExpiry      = $nextYear
    status             = 1
    municipalityId     = $municipalityA
}
Assert-Status "duplicate fleet number within A rejected" 409 $dupFleet.Status $dupFleet.Body

$crossDriver = Invoke-Api -Method POST -Path "/api/vehicles" -Body @{
    fleetNumber        = "0004"
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
    fleetNumber        = "0005"
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
    (Test-Enum $incidentA.Body.status "Reported" 1) `
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

# Second incident in A, for the cancellation path.
$incidentA2 = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description  = "Windscreen chipped by road debris."
    incidentType = 5
    vehicleId    = $vehicleA2Id
    driverId     = $driverAId
}
Assert-Status "log second incident in A" 201 $incidentA2.Status $incidentA2.Body
$incidentA2Id = $incidentA2.Body.id

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

# An incident with no job card can be deleted, and the row survives.
$disposableIncident = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description  = "Logged in error, no job card will be raised."
    incidentType = 5
    vehicleId    = $vehicleAId
    driverId     = $driverAId
}
Assert-Status "log an incident to delete" 201 $disposableIncident.Status $disposableIncident.Body
$disposableIncidentId = $disposableIncident.Body.id

$deleteDisposable = Invoke-Api -Method DELETE -Path "/api/incidents/$disposableIncidentId"
Assert-Status "incident without a job card can be deleted" 204 $deleteDisposable.Status $deleteDisposable.Body

$disposableGone = Invoke-Api -Method GET -Path "/api/incidents/$disposableIncidentId"
Assert-Status "deleted incident hidden by query filter" 404 $disposableGone.Status $disposableGone.Body

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
    (Test-Enum $jobCardA.Body.status "Open" 1) `
    "status was '$($jobCardA.Body.status)'"

Assert-True "transaction: incident advanced to JobCardCreated" `
    (Test-Enum $jobCardA.Body.incidentStatus "JobCardCreated" 3) `
    "incidentStatus was '$($jobCardA.Body.incidentStatus)'"

Assert-True "transaction: vehicle advanced to UnderRepair" `
    (Test-Enum $jobCardA.Body.vehicleStatus "UnderRepair" 2) `
    "vehicleStatus was '$($jobCardA.Body.vehicleStatus)'"

# Confirm independently, not just from the create response.
$vehicleAfter = Invoke-Api -Method GET -Path "/api/vehicles/$vehicleAId"
Assert-True "vehicle status persisted as UnderRepair" `
    (Test-Enum $vehicleAfter.Body.status "UnderRepair" 2) `
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
$jobCardBId = $jobCardB.Body.id

Assert-True "job card number restarts at $expectedFirst for B" `
    ($jobCardB.Body.jobCardNumber -eq $expectedFirst) `
    "number was '$($jobCardB.Body.jobCardNumber)'"

$missingJobCard = Invoke-Api -Method GET -Path ("/api/jobcards/" + (NewId))
Assert-Status "unknown job card id" 404 $missingJobCard.Status $missingJobCard.Body

# ---- Issue #35: soft delete coordination between Incident and JobCard ----
#
# Restrict does not block a soft delete, because IsDeleted is an UPDATE and
# the foreign key never fires. JobCard.Incident is a REQUIRED navigation, so
# EF Core uses an INNER JOIN for Include — a soft-deleted Incident would make
# its active JobCard disappear from query results entirely, which is worse
# than a null reference.
#
# The service guards against it. These assertions prove both halves: the
# delete is refused, AND the job card is still reachable afterwards.

$blockedIncident = Invoke-Api -Method DELETE -Path "/api/incidents/$incidentAId"
Assert-Status "incident with a job card cannot be deleted" 409 $blockedIncident.Status $blockedIncident.Body

$jobCardSurvives = Invoke-Api -Method GET -Path "/api/jobcards/$jobCardAId"
Assert-Status "job card still reachable after the refused incident delete" 200 $jobCardSurvives.Status $jobCardSurvives.Body

Assert-True "job card still resolves its incident" `
    (-not [string]::IsNullOrWhiteSpace($jobCardSurvives.Body.incidentDescription)) `
    "incidentDescription was '$($jobCardSurvives.Body.incidentDescription)'"

$incidentSurvives = Invoke-Api -Method GET -Path "/api/incidents/$incidentAId"
Assert-Status "incident still reachable after the refused delete" 200 $incidentSurvives.Status $incidentSurvives.Body

# ---------------------------------------------------------------- lifecycle

Write-Section "JobCard status lifecycle"

$badTransitionEnum = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 999
}
Assert-Status "undefined job card status rejected" 400 $badTransitionEnum.Status $badTransitionEnum.Body

$statusUnknown = Invoke-Api -Method PUT -Path ("/api/jobcards/" + (NewId) + "/status") -Body @{
    status = 2
}
Assert-Status "status update on unknown job card" 404 $statusUnknown.Status $statusUnknown.Body

# Open cannot jump straight to Completed.
$skipStep = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 3
}
Assert-Status "Open cannot skip to Completed" 409 $skipStep.Status $skipStep.Body

# Self-transition is not in the allowed set.
$selfTransition = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 1
}
Assert-Status "Open to Open rejected" 409 $selfTransition.Status $selfTransition.Body

# Open to InProgress.
$toInProgress = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 2
    notes  = "Mechanic has started on the coolant system."
}
Assert-Status "Open to InProgress" 200 $toInProgress.Status $toInProgress.Body

Assert-True "job card now InProgress" `
    (Test-Enum $toInProgress.Body.status "InProgress" 2) `
    "status was '$($toInProgress.Body.status)'"

Assert-True "notes updated on transition" `
    ($toInProgress.Body.notes -like "*coolant system*") `
    "notes were '$($toInProgress.Body.notes)'"

# InProgress to Completed cascades to the incident and the vehicle.
$toCompleted = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 3
    notes  = "Radiator replaced and pressure tested."
}
Assert-Status "InProgress to Completed" 200 $toCompleted.Status $toCompleted.Body

Assert-True "job card now Completed" `
    (Test-Enum $toCompleted.Body.status "Completed" 3) `
    "status was '$($toCompleted.Body.status)'"

Assert-True "DateCompleted stamped" `
    ($null -ne $toCompleted.Body.dateCompleted) `
    "dateCompleted was '$($toCompleted.Body.dateCompleted)'"

Assert-True "cascade: incident resolved" `
    (Test-Enum $toCompleted.Body.incidentStatus "Resolved" 4) `
    "incidentStatus was '$($toCompleted.Body.incidentStatus)'"

Assert-True "cascade: vehicle returned to Active" `
    (Test-Enum $toCompleted.Body.vehicleStatus "Active" 1) `
    "vehicleStatus was '$($toCompleted.Body.vehicleStatus)'"

# Confirm the vehicle independently, not from the transition response.
$vehicleReleased = Invoke-Api -Method GET -Path "/api/vehicles/$vehicleAId"
Assert-True "vehicle status persisted as Active" `
    (Test-Enum $vehicleReleased.Body.status "Active" 1) `
    "status was '$($vehicleReleased.Body.status)'"

# Completed is terminal.
$reopen = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 2
}
Assert-Status "Completed is terminal, cannot reopen" 409 $reopen.Status $reopen.Body

$cancelCompleted = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 4
}
Assert-Status "Completed cannot be cancelled" 409 $cancelCompleted.Status $cancelCompleted.Body

# A resolved incident cannot spawn a new job card.
$jobCardOnResolved = Invoke-Api -Method POST -Path "/api/incidents/$incidentAId/jobcards" -Body @{
    priority = 1
}
Assert-Status "no new job card on a resolved incident" 409 $jobCardOnResolved.Status $jobCardOnResolved.Body

# The cancellation path, on the second job card in A.
$jobCardA2 = Invoke-Api -Method POST -Path "/api/incidents/$incidentA2Id/jobcards" -Body @{
    priority = 1
    notes    = "Windscreen to be assessed."
}
Assert-Status "create second job card in A" 201 $jobCardA2.Status $jobCardA2.Body
$jobCardA2Id = $jobCardA2.Body.id

Assert-True "second job card in A numbered 002" `
    ($jobCardA2.Body.jobCardNumber -eq "JC-$today-002") `
    "number was '$($jobCardA2.Body.jobCardNumber)'"

$cancelled = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardA2Id/status" -Body @{
    status = 4
    notes  = "Damage within tolerance, no repair required."
}
Assert-Status "Open to Cancelled" 200 $cancelled.Status $cancelled.Body

Assert-True "cancel: incident reverted to Acknowledged" `
    (Test-Enum $cancelled.Body.incidentStatus "Acknowledged" 2) `
    "incidentStatus was '$($cancelled.Body.incidentStatus)'"

Assert-True "cancel: vehicle returned to Active" `
    (Test-Enum $cancelled.Body.vehicleStatus "Active" 1) `
    "vehicleStatus was '$($cancelled.Body.vehicleStatus)'"

$reviveCancelled = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardA2Id/status" -Body @{
    status = 2
}
Assert-Status "Cancelled is terminal" 409 $reviveCancelled.Status $reviveCancelled.Body

# A cancelled job card is still history, so it still blocks the delete.
$blockedByCancelled = Invoke-Api -Method DELETE -Path "/api/incidents/$incidentA2Id"
Assert-Status "incident with a cancelled job card cannot be deleted" 409 $blockedByCancelled.Status $blockedByCancelled.Body

$cancelledSurvives = Invoke-Api -Method GET -Path "/api/jobcards/$jobCardA2Id"
Assert-Status "cancelled job card still reachable" 200 $cancelledSurvives.Status $cancelledSurvives.Body

# ---------------------------------------------------------------- jobcard crud

Write-Section "JobCard list, update and assignment"

$listAll = Invoke-Api -Method GET -Path "/api/jobcards?pageSize=10"
Assert-Status "list job cards" 200 $listAll.Status $listAll.Body

Assert-True "list returns items with totalCount" `
    ($listAll.Body.totalCount -ge 3) `
    "totalCount was '$($listAll.Body.totalCount)'"

$byMunicipality = Invoke-Api -Method GET -Path "/api/jobcards?municipalityId=$municipalityA"
Assert-Status "filter job cards by municipality" 200 $byMunicipality.Status $byMunicipality.Body

Assert-True "municipality filter excludes other tenants" `
    ($byMunicipality.Body.totalCount -eq 2) `
    "totalCount was '$($byMunicipality.Body.totalCount)'"

$byStatus = Invoke-Api -Method GET -Path "/api/jobcards?status=3"
Assert-Status "filter job cards by status" 200 $byStatus.Status $byStatus.Body

$byPriority = Invoke-Api -Method GET -Path "/api/jobcards?priority=1"
Assert-Status "filter job cards by priority" 200 $byPriority.Status $byPriority.Body

$unassignedCards = Invoke-Api -Method GET -Path "/api/jobcards?unassigned=true"
Assert-Status "filter unassigned job cards" 200 $unassignedCards.Status $unassignedCards.Body

$badListEnum = Invoke-Api -Method GET -Path "/api/jobcards?status=999"
Assert-True "undefined status filter does not 500" `
    ($badListEnum.Status -eq 200 -or $badListEnum.Status -eq 400) `
    "status was $($badListEnum.Status)"

# Job card B is still Open, so it can be updated and assigned.
$updateCard = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardBId" -Body @{
    priority = 4
    notes    = "Escalated after a second failure."
}
Assert-Status "update priority and notes" 204 $updateCard.Status $updateCard.Body

$afterUpdate = Invoke-Api -Method GET -Path "/api/jobcards/$jobCardBId"
Assert-True "priority raised to Critical" `
    (Test-Enum $afterUpdate.Body.priority "Critical" 4) `
    "priority was '$($afterUpdate.Body.priority)'"

Assert-True "notes persisted" `
    ($afterUpdate.Body.notes -like "*second failure*") `
    "notes were '$($afterUpdate.Body.notes)'"

$badUpdateEnum = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardBId" -Body @{
    priority = 999
}
Assert-Status "undefined priority on update rejected" 400 $badUpdateEnum.Status $badUpdateEnum.Body

$updateUnknown = Invoke-Api -Method PUT -Path ("/api/jobcards/" + (NewId)) -Body @{
    priority = 2
}
Assert-Status "update on unknown job card" 404 $updateUnknown.Status $updateUnknown.Body

# Terminal cards keep their priority.
$terminalUpdate = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId" -Body @{
    priority = 1
    notes    = "Warranty claim submitted."
}
Assert-Status "priority change on a Completed card rejected" 409 $terminalUpdate.Status $terminalUpdate.Body

# Assignment must stay within the job card's municipality.
if ($supervisorB -and $mechanicB) {
    $assign = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardBId/assignment" -Body @{
        assignedSupervisorId = $supervisorB
        assignedMechanicId   = $mechanicB
    }
    Assert-Status "assign supervisor and mechanic from the same municipality" 200 $assign.Status $assign.Body

    Assert-True "supervisor name returned after assignment" `
        (-not [string]::IsNullOrWhiteSpace($assign.Body.assignedSupervisorName)) `
        "name was '$($assign.Body.assignedSupervisorName)'"

    Assert-True "mechanic name returned after assignment" `
        (-not [string]::IsNullOrWhiteSpace($assign.Body.assignedMechanicName)) `
        "name was '$($assign.Body.assignedMechanicName)'"
}

if ($supervisorA) {
    $crossAssign = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardBId/assignment" -Body @{
        assignedSupervisorId = $supervisorA
    }
    Assert-Status "supervisor from another municipality rejected on assign" 400 $crossAssign.Status $crossAssign.Body
}

if ($mechanicA) {
    $crossAssignMechanic = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardBId/assignment" -Body @{
        assignedMechanicId = $mechanicA
    }
    Assert-Status "mechanic from another municipality rejected on assign" 400 $crossAssignMechanic.Status $crossAssignMechanic.Body
}

# Null on the assignment endpoint clears, rather than leaving alone.
$clearAssignment = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardBId/assignment" -Body @{
    assignedSupervisorId = $null
    assignedMechanicId   = $null
}
Assert-Status "null assignment clears both" 200 $clearAssignment.Status $clearAssignment.Body

Assert-True "supervisor cleared" `
    ($null -eq $clearAssignment.Body.assignedSupervisorId) `
    "id was '$($clearAssignment.Body.assignedSupervisorId)'"

Assert-True "mechanic cleared" `
    ($null -eq $clearAssignment.Body.assignedMechanicId) `
    "id was '$($clearAssignment.Body.assignedMechanicId)'"

if ($supervisorA) {
    $assignTerminal = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/assignment" -Body @{
        assignedSupervisorId = $supervisorA
    }
    Assert-Status "Completed card cannot be reassigned" 409 $assignTerminal.Status $assignTerminal.Body
}

$assignUnknown = Invoke-Api -Method PUT -Path ("/api/jobcards/" + (NewId) + "/assignment") -Body @{
    assignedSupervisorId = $null
}
Assert-Status "assignment on unknown job card" 404 $assignUnknown.Status $assignUnknown.Body

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

$pagedJobCards = Invoke-Api -Method GET -Path "/api/jobcards?page=21474838&pageSize=100"
Assert-Status "job card pagination does not overflow" 200 $pagedJobCards.Status $pagedJobCards.Body

# ---------------------------------------------------------------- soft delete

Write-Section "Soft delete and fleet number reuse"

# Vehicle B is untouched by completed job cards, so use it for the delete path.
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
