# DriveOp API smoke test  (Windows PowerShell 5.1 compatible)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\test-api.ps1
#
# Setup order mirrors the real dependency chain:
#   Municipality -> Department -> WorkType -> Supervisor -> Mechanic
#     -> Driver -> Vehicle -> Incident -> JobCard
#
# Municipalities, supervisors and mechanics go in via sqlcmd because those
# endpoints do not exist yet. Departments and work types use the API.
#
# sqlcmd flags that matter:
#   -I       QUOTED_IDENTIFIER ON. SQL Server requires it for any DML against
#            a table carrying a filtered index, and Supervisors has one (the
#            unique filtered index enforcing one supervisor per department).
#            Without it every insert fails with error 1934.
#            Microsoft.Data.SqlClient sets this on by default, so the API was
#            never affected — only sqlcmd defaults it off.
#   -w 400   Output width. The default 80 wraps a 36-character GUID column,
#            which produced single-character "ids" and a downstream 400.
#   -h -1    No column headers.
#   -W       Trim trailing whitespace.

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

function Get-ProblemDetail {
    param($Body)

    if (-not $Body) { return $null }

    $names = $Body.PSObject.Properties.Name

    if ($names -contains "detail" -and $Body.detail) { return $Body.detail }

    # ValidationProblemDetails puts the useful information in 'errors', not
    # 'detail' — without this a model binding failure reads only as
    # "One or more validation errors occurred."
    if ($names -contains "errors" -and $Body.errors) {
        return ($Body.errors | ConvertTo-Json -Compress -Depth 4)
    }

    if ($names -contains "title" -and $Body.title) { return $Body.title }

    return ($Body | ConvertTo-Json -Compress -Depth 4)
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

        $detail = Get-ProblemDetail $Body
        if ($detail) { Write-Host "        $detail" -ForegroundColor DarkGray }

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

# Setup is load-bearing. A failure here means later assertions test nothing,
# so stop rather than skip and report a misleading pass count.
function Stop-Setup {
    param([string]$Reason, $Output)
    Write-Host ""
    Write-Host "SETUP FAILED: $Reason" -ForegroundColor Red
    if ($Output) {
        $Output | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }
    exit 1
}

function NewId { return [guid]::NewGuid().ToString() }

# A truncated or wrapped sqlcmd result produces a fragment that binds as a
# malformed Guid and surfaces as an opaque 400 much later. Fail here instead.
function Assert-Guid {
    param([string]$Value, [string]$What)

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Value, [ref]$parsed)) {
        Stop-Setup "$What is not a valid GUID: '$Value'"
    }
    return $Value
}

function Invoke-Sql {
    param([string]$Query)
    return sqlcmd -S $SqlServer -d $Database -I -h -1 -W -w 400 -Q $Query
}

function Get-SqlIds {
    param([string]$Query)
    $out = Invoke-Sql $Query
    return @($out |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' })
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
    Stop-Setup "API not reachable (status $($ping.Status)). Start it with: dotnet run --project DriveOp.Api"
}

Write-Section "Setting up municipalities"

$stamp = Get-Date -Format "HHmmss"
$codeA = "TA$stamp"
$codeB = "TB$stamp"

$municipalityInsert = "SET NOCOUNT ON; " +
    "INSERT INTO Municipalities (Id, Name, Code, Province, CreatedAt, IsDeleted) VALUES " +
    "(NEWID(), 'Test Municipality A $stamp', '$codeA', 'Gauteng', GETUTCDATE(), 0), " +
    "(NEWID(), 'Test Municipality B $stamp', '$codeB', 'Gauteng', GETUTCDATE(), 0); " +
    "SELECT CONVERT(varchar(36), Id) FROM Municipalities WHERE Code IN ('$codeA','$codeB') ORDER BY Code;"

$municipalityOutput = Invoke-Sql $municipalityInsert
$ids = Get-SqlIds $municipalityInsert

if ($ids.Count -lt 2) {
    Stop-Setup "Could not create municipalities." $municipalityOutput
}

$municipalityA = Assert-Guid $ids[0] "Municipality A id"
$municipalityB = Assert-Guid $ids[1] "Municipality B id"

Write-Host "  A: $municipalityA  ($codeA)"
Write-Host "  B: $municipalityB  ($codeB)"

# ---------------------------------------------------------------- departments

Write-Section "Departments"

$deptA = Invoke-Api -Method POST -Path "/api/departments" -Body @{
    name           = "Maintenance"
    description    = "Engine, electrical and routine servicing."
    municipalityId = $municipalityA
}
Assert-Status "create department in A" 201 $deptA.Status $deptA.Body

if (-not $deptA.Body.id) { Stop-Setup "Department A was not created." $deptA.Body }
$deptAId = Assert-Guid $deptA.Body.id "Department A id"

Assert-True "new department is unstaffed" `
    ($null -eq $deptA.Body.supervisorId) `
    "supervisorId was '$($deptA.Body.supervisorId)'"

$deptA2 = Invoke-Api -Method POST -Path "/api/departments" -Body @{
    name           = "Fabrication"
    municipalityId = $municipalityA
}
Assert-Status "create second department in A" 201 $deptA2.Status $deptA2.Body

# Tenant-scoped uniqueness: B may use the same department name.
$deptB = Invoke-Api -Method POST -Path "/api/departments" -Body @{
    name           = "Maintenance"
    municipalityId = $municipalityB
}
Assert-Status "same department name allowed in B" 201 $deptB.Status $deptB.Body

if (-not $deptA2.Body.id -or -not $deptB.Body.id) {
    Stop-Setup "Departments were not fully created."
}

$deptA2Id = Assert-Guid $deptA2.Body.id "Department A2 id"
$deptBId  = Assert-Guid $deptB.Body.id "Department B id"

$dupDept = Invoke-Api -Method POST -Path "/api/departments" -Body @{
    name           = "Maintenance"
    municipalityId = $municipalityA
}
Assert-Status "duplicate department name within A rejected" 409 $dupDept.Status $dupDept.Body

# Whitespace must not create a second 'Maintenance' that routes differently.
$whitespaceDept = Invoke-Api -Method POST -Path "/api/departments" -Body @{
    name           = "  Maintenance  "
    municipalityId = $municipalityA
}
Assert-Status "whitespace-padded duplicate rejected" 409 $whitespaceDept.Status $whitespaceDept.Body

$deptUnknownMuni = Invoke-Api -Method POST -Path "/api/departments" -Body @{
    name           = "Orphan"
    municipalityId = (NewId)
}
Assert-Status "department for unknown municipality rejected" 400 $deptUnknownMuni.Status $deptUnknownMuni.Body

$readDept = Invoke-Api -Method GET -Path "/api/departments/$deptAId"
Assert-Status "read department by id" 200 $readDept.Status $readDept.Body

$deptMissing = Invoke-Api -Method GET -Path ("/api/departments/" + (NewId))
Assert-Status "unknown department id" 404 $deptMissing.Status $deptMissing.Body

$deptList = Invoke-Api -Method GET -Path "/api/departments?municipalityId=$municipalityA"
Assert-Status "list departments by municipality" 200 $deptList.Status $deptList.Body

Assert-True "municipality filter excludes other tenants" `
    ($deptList.Body.totalCount -eq 2) `
    "totalCount was '$($deptList.Body.totalCount)'"

$unstaffed = Invoke-Api -Method GET -Path "/api/departments?municipalityId=$municipalityA&unstaffed=true"
Assert-Status "filter unstaffed departments" 200 $unstaffed.Status $unstaffed.Body

Assert-True "both departments currently unstaffed" `
    ($unstaffed.Body.totalCount -eq 2) `
    "totalCount was '$($unstaffed.Body.totalCount)'"

$deptUpdate = Invoke-Api -Method PUT -Path "/api/departments/$deptA2Id" -Body @{
    name        = "Fabrication and Welding"
    description = "Panel work, welding and body repairs."
}
Assert-Status "update department" 204 $deptUpdate.Status $deptUpdate.Body

$deptRenameClash = Invoke-Api -Method PUT -Path "/api/departments/$deptA2Id" -Body @{
    name = "Maintenance"
}
Assert-Status "renaming onto an existing name rejected" 409 $deptRenameClash.Status $deptRenameClash.Body

# ---------------------------------------------------------------- work types

Write-Section "Work types and routing"

$workTypeA = Invoke-Api -Method POST -Path "/api/worktypes" -Body @{
    name         = "Engine Failure"
    departmentId = $deptAId
}
Assert-Status "create work type in A" 201 $workTypeA.Status $workTypeA.Body

if (-not $workTypeA.Body.id) { Stop-Setup "Work type A was not created." $workTypeA.Body }
$workTypeAId = Assert-Guid $workTypeA.Body.id "Work type A id"

Assert-True "work type inherits the department's municipality" `
    ($workTypeA.Body.municipalityId -eq $municipalityA) `
    "municipalityId was '$($workTypeA.Body.municipalityId)'"

Assert-True "work type resolves its department name" `
    ($workTypeA.Body.departmentName -eq "Maintenance") `
    "departmentName was '$($workTypeA.Body.departmentName)'"

Assert-True "work type shows no supervisor while the department is unstaffed" `
    ($null -eq $workTypeA.Body.supervisorId) `
    "supervisorId was '$($workTypeA.Body.supervisorId)'"

$workTypeA2 = Invoke-Api -Method POST -Path "/api/worktypes" -Body @{
    name         = "Body Damage"
    departmentId = $deptA2Id
}
Assert-Status "create second work type in A" 201 $workTypeA2.Status $workTypeA2.Body

$workTypeB = Invoke-Api -Method POST -Path "/api/worktypes" -Body @{
    name         = "Engine Failure"
    departmentId = $deptBId
}
Assert-Status "same work type name allowed in B" 201 $workTypeB.Status $workTypeB.Body

if (-not $workTypeA2.Body.id -or -not $workTypeB.Body.id) {
    Stop-Setup "Work types were not fully created."
}

$workTypeA2Id = Assert-Guid $workTypeA2.Body.id "Work type A2 id"
$workTypeBId  = Assert-Guid $workTypeB.Body.id "Work type B id"

$dupWorkType = Invoke-Api -Method POST -Path "/api/worktypes" -Body @{
    name         = "Engine Failure"
    departmentId = $deptA2Id
}
Assert-Status "duplicate work type name within A rejected" 409 $dupWorkType.Status $dupWorkType.Body

$workTypeUnknownDept = Invoke-Api -Method POST -Path "/api/worktypes" -Body @{
    name         = "Orphan"
    departmentId = (NewId)
}
Assert-Status "work type for unknown department rejected" 400 $workTypeUnknownDept.Status $workTypeUnknownDept.Body

# Remapping within the municipality is the point of routing being data.
$remap = Invoke-Api -Method PUT -Path "/api/worktypes/$workTypeA2Id" -Body @{
    name         = "Body Damage"
    departmentId = $deptAId
}
Assert-Status "remap work type to another department in the same municipality" 204 $remap.Status $remap.Body

$afterRemap = Invoke-Api -Method GET -Path "/api/worktypes/$workTypeA2Id"
Assert-True "remap took effect" `
    ($afterRemap.Body.departmentId -eq $deptAId) `
    "departmentId was '$($afterRemap.Body.departmentId)'"

# Remapping across municipalities would route incidents into another tenant.
$crossRemap = Invoke-Api -Method PUT -Path "/api/worktypes/$workTypeA2Id" -Body @{
    name         = "Body Damage"
    departmentId = $deptBId
}
Assert-Status "cross-municipality remap rejected" 400 $crossRemap.Status $crossRemap.Body

$byDepartment = Invoke-Api -Method GET -Path "/api/worktypes?departmentId=$deptAId"
Assert-Status "filter work types by department" 200 $byDepartment.Status $byDepartment.Body

Assert-True "both work types now sit under Maintenance" `
    ($byDepartment.Body.totalCount -eq 2) `
    "totalCount was '$($byDepartment.Body.totalCount)'"

# A department with work types attached cannot be deleted.
$deptWithWorkTypes = Invoke-Api -Method DELETE -Path "/api/departments/$deptAId"
Assert-Status "department with work types cannot be deleted" 409 $deptWithWorkTypes.Status $deptWithWorkTypes.Body

# An empty department can be.
$emptyDept = Invoke-Api -Method POST -Path "/api/departments" -Body @{
    name           = "Temporary"
    municipalityId = $municipalityA
}
Assert-Status "create an empty department" 201 $emptyDept.Status $emptyDept.Body
$emptyDeptId = $emptyDept.Body.id

$deleteEmpty = Invoke-Api -Method DELETE -Path "/api/departments/$emptyDeptId"
Assert-Status "empty department can be deleted" 204 $deleteEmpty.Status $deleteEmpty.Body

$emptyGone = Invoke-Api -Method GET -Path "/api/departments/$emptyDeptId"
Assert-Status "deleted department hidden by query filter" 404 $emptyGone.Status $emptyGone.Body

# ---------------------------------------------------------------- staff

Write-Section "Setting up supervisors and mechanics"

# No endpoints for these yet, so raw inserts. Supervisor.DepartmentId is
# required and unique per department, which is the one-supervisor-per-department
# rule enforced at the database level.
$staffInsert = "SET NOCOUNT ON; " +
    "DECLARE @supA uniqueidentifier = NEWID(), @supB uniqueidentifier = NEWID(); " +
    "DECLARE @mechA uniqueidentifier = NEWID(), @mechB uniqueidentifier = NEWID(); " +
    "INSERT INTO Supervisors (Id, Name, Surname, Email, MunicipalityId, DepartmentId, CreatedAt, IsDeleted) VALUES " +
    "(@supA, 'Thandi', 'SupA$stamp', 'a@test.gov.za', '$municipalityA', '$deptAId', GETUTCDATE(), 0), " +
    "(@supB, 'Sipho', 'SupB$stamp', 'b@test.gov.za', '$municipalityB', '$deptBId', GETUTCDATE(), 0); " +
    "INSERT INTO Mechanics (Id, Name, Surname, MunicipalityId, SupervisorId, DepartmentId, CreatedAt, IsDeleted) VALUES " +
    "(@mechA, 'Lerato', 'MechA$stamp', '$municipalityA', @supA, '$deptAId', GETUTCDATE(), 0), " +
    "(@mechB, 'Bongani', 'MechB$stamp', '$municipalityB', @supB, '$deptBId', GETUTCDATE(), 0); " +
    "SELECT CONVERT(varchar(36), @supA) UNION ALL " +
    "SELECT CONVERT(varchar(36), @supB) UNION ALL " +
    "SELECT CONVERT(varchar(36), @mechA) UNION ALL " +
    "SELECT CONVERT(varchar(36), @mechB);"

$staffOutput = Invoke-Sql $staffInsert
$staffIds = @($staffOutput |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' })

if ($staffIds.Count -lt 4) {
    Stop-Setup "Could not create supervisors and mechanics (got $($staffIds.Count) of 4 ids)." $staffOutput
}

$supervisorA = Assert-Guid $staffIds[0] "Supervisor A id"
$supervisorB = Assert-Guid $staffIds[1] "Supervisor B id"
$mechanicA   = Assert-Guid $staffIds[2] "Mechanic A id"
$mechanicB   = Assert-Guid $staffIds[3] "Mechanic B id"

Write-Host "  Supervisor A: $supervisorA  (Maintenance, municipality A)"
Write-Host "  Supervisor B: $supervisorB  (Maintenance, municipality B)"
Write-Host "  Mechanic A:   $mechanicA"
Write-Host "  Mechanic B:   $mechanicB"

# One supervisor per department, enforced by the unique filtered index. There
# is no endpoint for supervisors yet, so this is the only way to test it.
$secondSupervisorSql = "SET NOCOUNT ON; " +
    "BEGIN TRY " +
    "INSERT INTO Supervisors (Id, Name, Surname, Email, MunicipalityId, DepartmentId, CreatedAt, IsDeleted) " +
    "VALUES (NEWID(), 'Second', 'Sup$stamp', 'x@test.gov.za', '$municipalityA', '$deptAId', GETUTCDATE(), 0); " +
    "SELECT 'INSERTED'; END TRY BEGIN CATCH SELECT 'REJECTED'; END CATCH;"

$secondSupervisorOut = Invoke-Sql $secondSupervisorSql

Assert-True "a second supervisor in the same department is rejected by the index" `
    (($secondSupervisorOut -join " ") -match "REJECTED") `
    "sqlcmd returned '$($secondSupervisorOut -join ' | ')'"

# ---------------------------------------------------------------- routing

Write-Section "Routing chain: work type to department to supervisor"

$routedWorkType = Invoke-Api -Method GET -Path "/api/worktypes/$workTypeAId"
Assert-Status "read work type after staffing" 200 $routedWorkType.Status $routedWorkType.Body

Assert-True "work type now resolves a supervisor through its department" `
    ($routedWorkType.Body.supervisorId -eq $supervisorA) `
    "supervisorId was '$($routedWorkType.Body.supervisorId)'"

Assert-True "work type carries the supervisor name" `
    (-not [string]::IsNullOrWhiteSpace($routedWorkType.Body.supervisorName)) `
    "supervisorName was '$($routedWorkType.Body.supervisorName)'"

$staffedDept = Invoke-Api -Method GET -Path "/api/departments/$deptAId"
Assert-True "department reports its supervisor" `
    ($staffedDept.Body.supervisorId -eq $supervisorA) `
    "supervisorId was '$($staffedDept.Body.supervisorId)'"

Assert-True "department reports its mechanic count" `
    ($staffedDept.Body.mechanicCount -eq 1) `
    "mechanicCount was '$($staffedDept.Body.mechanicCount)'"

Assert-True "department reports its work type count" `
    ($staffedDept.Body.workTypeCount -eq 2) `
    "workTypeCount was '$($staffedDept.Body.workTypeCount)'"

$stillUnstaffed = Invoke-Api -Method GET -Path "/api/departments?municipalityId=$municipalityA&unstaffed=true"
Assert-True "only the unstaffed department is now listed" `
    ($stillUnstaffed.Body.totalCount -eq 1) `
    "totalCount was '$($stillUnstaffed.Body.totalCount)'"

$deptWithSupervisor = Invoke-Api -Method DELETE -Path "/api/departments/$deptAId"
Assert-Status "department with a supervisor cannot be deleted" 409 $deptWithSupervisor.Status $deptWithSupervisor.Body

$nextYear = (Get-Date).AddYears(1).ToString("yyyy-MM-dd")
$twoYears = (Get-Date).AddYears(2).ToString("yyyy-MM-dd")

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

$driverB = Invoke-Api -Method POST -Path "/api/drivers" -Body @{
    name           = "Naledi"
    surname        = "Khumalo"
    licenseNumber  = "$codeB-DL-001"
    municipalityId = $municipalityB
}
Assert-Status "create driver in B" 201 $driverB.Status $driverB.Body

if (-not $driverA.Body.id -or -not $driverB.Body.id) { Stop-Setup "Drivers were not created." }

$driverAId = Assert-Guid $driverA.Body.id "Driver A id"
$driverBId = Assert-Guid $driverB.Body.id "Driver B id"

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

if (-not $vehicleA.Body.id -or -not $vehicleB.Body.id -or -not $vehicleA2.Body.id) {
    Stop-Setup "Vehicles were not created."
}

$vehicleAId  = Assert-Guid $vehicleA.Body.id "Vehicle A id"
$vehicleBId  = Assert-Guid $vehicleB.Body.id "Vehicle B id"
$vehicleA2Id = Assert-Guid $vehicleA2.Body.id "Vehicle A2 id"

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
    description = "Engine overheating on the N1 near Midrand."
    workTypeId  = $workTypeAId
    vehicleId   = $vehicleAId
    driverId    = $driverAId
}
Assert-Status "log incident in A" 201 $incidentA.Status $incidentA.Body

if (-not $incidentA.Body.id) { Stop-Setup "Incident A was not created." $incidentA.Body }
$incidentAId = Assert-Guid $incidentA.Body.id "Incident A id"

Assert-True "incident status set server-side to Reported" `
    (Test-Enum $incidentA.Body.status "Reported" 1) `
    "status was '$($incidentA.Body.status)'"

Assert-True "hasJobCard false on a new incident" `
    ($incidentA.Body.hasJobCard -eq $false) `
    "hasJobCard was '$($incidentA.Body.hasJobCard)'"

# The department is derived from the work type, never sent by the client.
Assert-True "incident department derived from the work type" `
    ($incidentA.Body.departmentId -eq $deptAId) `
    "departmentId was '$($incidentA.Body.departmentId)'"

Assert-True "incident resolves its work type name" `
    ($incidentA.Body.workTypeName -eq "Engine Failure") `
    "workTypeName was '$($incidentA.Body.workTypeName)'"

$incidentB = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description = "Brake failure reported by the driver."
    workTypeId  = $workTypeBId
    vehicleId   = $vehicleBId
    driverId    = $driverBId
}
Assert-Status "log incident in B" 201 $incidentB.Status $incidentB.Body

$incidentA2 = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description = "Windscreen chipped by road debris."
    workTypeId  = $workTypeA2Id
    vehicleId   = $vehicleA2Id
    driverId    = $driverAId
}
Assert-Status "log second incident in A" 201 $incidentA2.Status $incidentA2.Body

if (-not $incidentB.Body.id -or -not $incidentA2.Body.id) {
    Stop-Setup "Incidents were not fully created."
}

$incidentBId  = Assert-Guid $incidentB.Body.id "Incident B id"
$incidentA2Id = Assert-Guid $incidentA2.Body.id "Incident A2 id"

# A work type from another municipality would route into the wrong tenant.
$crossWorkType = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description = "Work type from B against a vehicle in A."
    workTypeId  = $workTypeBId
    vehicleId   = $vehicleAId
    driverId    = $driverAId
}
Assert-Status "cross-municipality work type rejected" 400 $crossWorkType.Status $crossWorkType.Body

$unknownWorkType = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description = "Unknown work type."
    workTypeId  = (NewId)
    vehicleId   = $vehicleAId
    driverId    = $driverAId
}
Assert-Status "unknown work type rejected" 400 $unknownWorkType.Status $unknownWorkType.Body

$crossIncident = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description = "Vehicle from A with driver from B, should be rejected."
    workTypeId  = $workTypeAId
    vehicleId   = $vehicleAId
    driverId    = $driverBId
}
Assert-Status "cross-municipality incident rejected" 400 $crossIncident.Status $crossIncident.Body

$unknownVehicle = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description = "Unknown vehicle."
    workTypeId  = $workTypeAId
    vehicleId   = (NewId)
    driverId    = $driverAId
}
Assert-Status "unknown vehicle rejected" 400 $unknownVehicle.Status $unknownVehicle.Body

$emptyDescription = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description = ""
    workTypeId  = $workTypeAId
    vehicleId   = $vehicleAId
    driverId    = $driverAId
}
Assert-Status "empty description rejected by annotations" 400 $emptyDescription.Status $emptyDescription.Body

$byWorkType = Invoke-Api -Method GET -Path "/api/incidents?workTypeId=$workTypeAId"
Assert-Status "filter incidents by work type" 200 $byWorkType.Status $byWorkType.Body

$byDept = Invoke-Api -Method GET -Path "/api/incidents?departmentId=$deptAId"
Assert-Status "filter incidents by department" 200 $byDept.Status $byDept.Body

Assert-True "both incidents in A route to Maintenance" `
    ($byDept.Body.totalCount -eq 2) `
    "totalCount was '$($byDept.Body.totalCount)'"

$incidentFilter = "/api/incidents?vehicleId=" + $vehicleAId + "&pageSize=5"
$filtered = Invoke-Api -Method GET -Path $incidentFilter
Assert-Status "filter incidents by vehicle" 200 $filtered.Status $filtered.Body

# A work type used on an incident is retained as history.
$workTypeInUse = Invoke-Api -Method DELETE -Path "/api/worktypes/$workTypeAId"
Assert-Status "work type used on an incident cannot be deleted" 409 $workTypeInUse.Status $workTypeInUse.Body

# An incident with no job card can be deleted, and the row survives.
$disposableIncident = Invoke-Api -Method POST -Path "/api/incidents" -Body @{
    description = "Logged in error, no job card will be raised."
    workTypeId  = $workTypeAId
    vehicleId   = $vehicleAId
    driverId    = $driverAId
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

$crossSupervisor = Invoke-Api -Method POST -Path "/api/incidents/$incidentAId/jobcards" -Body @{
    priority             = 2
    assignedSupervisorId = $supervisorB
}
Assert-Status "supervisor from another municipality rejected" 400 $crossSupervisor.Status $crossSupervisor.Body

$jobCardA = Invoke-Api -Method POST -Path "/api/incidents/$incidentAId/jobcards" -Body @{
    priority             = 3
    notes                = "Coolant leak suspected. Needs a full inspection."
    assignedSupervisorId = $supervisorA
    assignedMechanicId   = $mechanicA
}
Assert-Status "create job card from incident in A" 201 $jobCardA.Status $jobCardA.Body

if (-not $jobCardA.Body.id) { Stop-Setup "Job card A was not created." $jobCardA.Body }
$jobCardAId = Assert-Guid $jobCardA.Body.id "Job card A id"

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

Assert-True "job card carries the assigned mechanic" `
    ($jobCardA.Body.assignedMechanicId -eq $mechanicA) `
    "assignedMechanicId was '$($jobCardA.Body.assignedMechanicId)'"

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

$jobCardB = Invoke-Api -Method POST -Path "/api/incidents/$incidentBId/jobcards" -Body @{
    priority = 2
    notes    = "Brake pads to be replaced."
}
Assert-Status "create job card from incident in B" 201 $jobCardB.Status $jobCardB.Body

if (-not $jobCardB.Body.id) { Stop-Setup "Job card B was not created." $jobCardB.Body }
$jobCardBId = Assert-Guid $jobCardB.Body.id "Job card B id"

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
# its active JobCard disappear from query results entirely.

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

$skipStep = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 3
}
Assert-Status "Open cannot skip to Completed" 409 $skipStep.Status $skipStep.Body

$selfTransition = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 1
}
Assert-Status "Open to Open rejected" 409 $selfTransition.Status $selfTransition.Body

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

$vehicleReleased = Invoke-Api -Method GET -Path "/api/vehicles/$vehicleAId"
Assert-True "vehicle status persisted as Active" `
    (Test-Enum $vehicleReleased.Body.status "Active" 1) `
    "status was '$($vehicleReleased.Body.status)'"

$reopen = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 2
}
Assert-Status "Completed is terminal, cannot reopen" 409 $reopen.Status $reopen.Body

$cancelCompleted = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/status" -Body @{
    status = 4
}
Assert-Status "Completed cannot be cancelled" 409 $cancelCompleted.Status $cancelCompleted.Body

$jobCardOnResolved = Invoke-Api -Method POST -Path "/api/incidents/$incidentAId/jobcards" -Body @{
    priority = 1
}
Assert-Status "no new job card on a resolved incident" 409 $jobCardOnResolved.Status $jobCardOnResolved.Body

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

$byJcPriority = Invoke-Api -Method GET -Path "/api/jobcards?priority=1"
Assert-Status "filter job cards by priority" 200 $byJcPriority.Status $byJcPriority.Body

$unassignedCards = Invoke-Api -Method GET -Path "/api/jobcards?unassigned=true"
Assert-Status "filter unassigned job cards" 200 $unassignedCards.Status $unassignedCards.Body

$badListEnum = Invoke-Api -Method GET -Path "/api/jobcards?status=999"
Assert-True "undefined status filter does not 500" `
    ($badListEnum.Status -eq 200 -or $badListEnum.Status -eq 400) `
    "status was $($badListEnum.Status)"

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

$terminalUpdate = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId" -Body @{
    priority = 1
    notes    = "Warranty claim submitted."
}
Assert-Status "priority change on a Completed card rejected" 409 $terminalUpdate.Status $terminalUpdate.Body

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

$crossAssign = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardBId/assignment" -Body @{
    assignedSupervisorId = $supervisorA
}
Assert-Status "supervisor from another municipality rejected on assign" 400 $crossAssign.Status $crossAssign.Body

$crossAssignMechanic = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardBId/assignment" -Body @{
    assignedMechanicId = $mechanicA
}
Assert-Status "mechanic from another municipality rejected on assign" 400 $crossAssignMechanic.Status $crossAssignMechanic.Body

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

$assignTerminal = Invoke-Api -Method PUT -Path "/api/jobcards/$jobCardAId/assignment" -Body @{
    assignedSupervisorId = $supervisorA
}
Assert-Status "Completed card cannot be reassigned" 409 $assignTerminal.Status $assignTerminal.Body

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

$pagedDepts = Invoke-Api -Method GET -Path "/api/departments?page=21474838&pageSize=100"
Assert-Status "department pagination does not overflow" 200 $pagedDepts.Status $pagedDepts.Body

$pagedWorkTypes = Invoke-Api -Method GET -Path "/api/worktypes?page=21474838&pageSize=100"
Assert-Status "work type pagination does not overflow" 200 $pagedWorkTypes.Status $pagedWorkTypes.Body

# ---------------------------------------------------------------- soft delete

Write-Section "Soft delete and fleet number reuse"

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
