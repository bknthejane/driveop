# DriveOp

A multi-tenant fleet management system for South African municipalities —
vehicles, drivers, and the full incident-to-repair lifecycle.

Built with ASP.NET Core, Entity Framework Core and SQL Server.
**Deliberately framework-free.**

---

## Why this exists

I'd been building production systems on [ABP](https://abp.io/), and I was
productive with it — but I couldn't explain what it was doing underneath. Audit
fields populated themselves. Repositories appeared without me writing them.
Soft delete happened somewhere I'd never looked.

So I rebuilt DriveOp from an empty folder with no application framework, to
understand the parts ABP had been handling for me:

| ABP gave me | What it actually is |
|---|---|
| `FullAuditedEntity` | An override of `SaveChanges` that walks EF Core's change tracker |
| Soft delete "just working" | Converting `EntityState.Deleted` to a scoped UPDATE, plus global query filters |
| `IRepository<T>` | A `DbContext` and a service layer you write yourself |
| Auto-registered services | Explicit DI registration in a composition root you can read |
| Unit of work | `SaveChanges` batching, plus explicit transactions where they're needed |
| A 6-project solution template | Layering, which is about dependency direction — not project count |

I then went further and tore down two earlier attempts at this system — an
ASP.NET MVC 5 / EF6 version and an ABP one — documenting their entity models,
business rules, permissions and bugs. **Neither had any server-side
authorisation on domain endpoints**; one corrupted a vehicle's VIN on every
record it created. What I built instead is shaped by what those got wrong.

I also read the functional specifications municipalities actually put out to
tender, and built to those rather than to guesswork. Details in
[Implementation decisions](#implementation-decisions).

---

## Status

Actively in development.

**Working**

- Domain model — 9 entities, explicit relationship configuration, migrations
- Audit fields and soft delete via change-tracker interception
- Optimistic concurrency on every entity
- Tenant-scoped filtered unique indexes
- Global exception handling with RFC 9457 ProblemDetails and trace ids
- Departments and work types as entities, with data-driven routing
- Vehicles and Drivers — full CRUD, paginated, filtered
- Incidents — logging with cross-tenant validation
- JobCards — generated from an incident inside a transaction, with an enforced
  status lifecycle, assignment, and per-tenant daily numbering
- 160-assertion API smoke test

**In progress**

- Auto-created job cards on incident logging
- Task and part lines, so labour and cost are recordable
- Odometer readings and driver licence expiries
- Job card status history

**Not started**

- JWT authentication and role-based authorisation
- Next.js frontend

---

## Stack

**Backend** — ASP.NET Core 10 Web API · Entity Framework Core 10 · SQL Server
**Planned frontend** — Next.js (App Router) · TypeScript
**Tooling** — CodeRabbit for automated review · GitGuardian for secret scanning

---

## Domain model

```
Municipality (the tenant)
├── Departments ───── have one ────── Supervisor
│   ├── WorkTypes                     (one per department)
│   └── Mechanics
├── Vehicles ──────── assigned to ──── Driver
└── Drivers

Incident (logged against a Vehicle + Driver, categorised by WorkType)
└── JobCard (generated from an Incident, routed via WorkType → Department
             → Supervisor, worked by a Mechanic)
```

**Core flow:** a driver logs an incident against a vehicle, choosing a work
type → the work type determines the department, and the department its
supervisor → a job card is generated and the vehicle goes to `UnderRepair` →
status moves `Open → InProgress → Completed` → on completion the incident
resolves and the vehicle returns to `Active`.

**Roles:** Super Admin · Municipality Admin · Supervisor · Driver · Mechanic

---

## Architecture

```
DriveOp.Api/
├── Entities/              # Domain models — no framework dependencies
│   ├── Common/            # BaseEntity, IAuditable, ISoftDeletable
│   └── Enums/
├── Data/
│   ├── DriveOpDbContext.cs
│   └── Configurations/    # One IEntityTypeConfiguration per entity
├── DTOs/                  # Separate shapes per operation
├── Services/              # Business logic — returns ServiceResult, not HTTP types
├── Controllers/           # Validate, delegate, translate to status codes
└── Common/                # ServiceResult<T>, transition rules, exception handler
```

Requests flow one way: **Controller → Service → DbContext → Database**, and the
mapped DTO comes back. Business logic never appears in a controller; HTTP
concerns never appear in a service.

`Entities/` references nothing — not ASP.NET Core, not EF Core. That folder
could move into its own project and still compile, which is what makes this
layered rather than three folders with nice names.

---

## Implementation decisions

### Soft delete via change-tracker interception

`SaveChanges` is overridden to walk EF Core's change tracker before the SQL is
generated. Entries marked `Deleted` are reset to `Unchanged`, their
`IsDeleted`/`DeletedAt` fields set, and **only those two properties marked as
modified** — so the UPDATE touches two columns rather than every mapped
property, and a stale tracked entity can't overwrite concurrent changes.

Both `acceptAllChangesOnSuccess` overloads are overridden, not the parameterless
ones. The parameterless methods delegate to these, so guarding only those would
let some callers bypass the audit rules entirely and turn soft deletes into
physical deletes.

Global query filters then exclude soft-deleted rows from every query
automatically, including inside `Include`.

### `DeleteBehavior.Restrict` on every relationship

Soft delete means `IsDeleted = true` is an **UPDATE**, so a foreign key
constraint never fires. Configuring `Cascade` would be decorative — it would
never run, while leaving orphaned children pointing at a hidden parent.

`Restrict` instead acts as a genuine safety net against anything that bypasses
the soft-delete path: a manual SQL script, a seeding bug, `ExecuteDeleteAsync`.
Cascading a soft delete is then an explicit, transactional decision in the
service layer, with a 409 when children exist.

It also avoids SQL Server's multiple-cascade-path restriction: `Vehicle` reaches
`Municipality` both directly and via `AssignedDriver`, and `Mechanic` reaches it
both directly and via `Supervisor`.

**The subtlety worth naming:** soft-deleting a parent leaves children pointing
at a hidden row, and what happens next depends on the navigation's nullability.
A nullable navigation gives a `LEFT JOIN`, so the child still appears with a
null name. A **required** navigation gives an `INNER JOIN`, so the child
**disappears from query results entirely** — worse than a null reference,
because nothing looks wrong. That's why parent deletes are guarded in the
service layer and asserted in the test suite.

### Tenant-scoped identifiers

Fleet numbers are internal identifiers a municipality assigns itself, so
`(MunicipalityId, FleetNumber)` is unique rather than `FleetNumber` alone —
two municipalities can each have vehicle `0001`. Registration numbers and
driving licences are issued nationally, so those stay globally unique.

**The principle: the scope of a uniqueness constraint should match the scope of
the authority that issues the value.**

Every unique index is filtered on `IsDeleted = 0`, so the database agrees with
the query filter. Without that, the service reports a soft-deleted fleet number
as available and the insert then violates the index.

### Routing as data, not code

The earlier ABP version hardcoded three departments as free-text strings in a
frontend dropdown and mapped seven work types to them in a `switch`. A second
municipality with a different workshop structure couldn't be represented, and
`"Maintenance"` versus `"maintenence"` routed differently.

`Department` and `WorkType` are entities scoped per municipality, so the
work-type-to-department mapping is data a municipality edits without a deploy.
One supervisor per department, enforced by a unique filtered index on
`DepartmentId` — `HasOne().WithOne()` enforces it in the model, the index
enforces it in the database.

`Incident.DepartmentId` is derived from the work type and **stored**, not
computed at read time: it's a point-in-time fact, so remapping a work type next
year doesn't rewrite which department handled historical incidents.

### Atomic number allocation

Job card numbers are `JC-yyyyMMdd-001`, resetting daily per municipality.

Both earlier versions derived the next number by reading the highest existing
one, which has two bugs in one. Two concurrent requests read the same value and
collide. And `OrderByDescending` on a string ranks `-999` above `-1000`, so
crossing 999 in a day makes the generator propose 1000 forever — **permanently
broken for the rest of that day.**

Allocation is now a single statement against a counter table:

```sql
UPDATE NumberSequences
SET LastValue = LastValue + 1
OUTPUT INSERTED.LastValue
WHERE MunicipalityId = @m AND SequenceName = @s AND PeriodKey = @p
```

The row lock SQL Server takes for that statement is what serialises concurrent
callers — no isolation level change, no retry loop. It's the only raw SQL in the
project, because EF Core has no LINQ expression for `OUTPUT` and read-then-write
in LINQ would move the race rather than remove it. The command enlists in the
caller's ambient transaction, so the counter rolls back if the job card insert
fails.

### Enforced status transitions

Valid transitions are declared as data in `JobCardStatusTransitions` rather than
scattered as comparisons, so the rules read in one place and are unit-testable
without EF Core. `Completed` and `Cancelled` are terminal.

An invalid transition returns **409, not 400** — the request is well-formed and
the job card exists, so it's the current state that makes it impossible.

Completing a card stamps `DateCompleted`, resolves the incident and returns the
vehicle to `Active`, all in one transaction.

### Optimistic concurrency

`RowVersion` on every entity, configured in one loop over the model rather than
per entity. SQL Server maintains the column, so EF Core includes the original
value in each UPDATE's `WHERE` clause and a losing write affects zero rows.

This matters for transitions specifically: without it, two concurrent requests
could both validate `Open` and commit different transitions, leaving a card
marked `InProgress` while its incident says `Acknowledged` — a state the
transition table says is impossible, reached silently.

### DTOs at every boundary

Entities are never exposed. Each operation gets its own shape:

- Create DTOs have no `Id` or audit fields — a client **physically cannot** set
  them, so over-posting is structurally impossible rather than runtime-checked
- `UpdateVehicleDto` omits `FleetNumber` and `MunicipalityId` — both immutable
  after creation; transferring a vehicle between municipalities is a distinct
  operation with its own rules
- List DTOs are lighter, so list queries select fewer columns

Enums crossing the boundary are checked with `Enum.IsDefined`. `[Required]` on a
non-nullable enum only checks for absence, not validity — without the check,
`status: 999` is accepted and persisted as an int that maps to no defined name.

### Projection over eager loading on lists

List endpoints project inside `IQueryable` rather than calling `Include` and
mapping afterwards. `Include` emits a `LEFT JOIN` returning every column of
every joined table; projection selects only the columns the DTO needs.

The generated SQL also pushes `OFFSET/FETCH` into a subquery so the join runs
against the current page rather than the full result set.

### Services return results, not HTTP types

`ServiceResult<T>` carries a success flag, a value, and an error type
(`NotFound`, `Conflict`, `Validation`). The controller maps error types to
status codes in one place. The service layer has no dependency on ASP.NET Core,
so it's testable without a web host and reusable from a background job.

The properties are `private init`, settable only through factory methods — you
can't construct a result that claims success while carrying an error.

---

## Testing

A PowerShell smoke test covers the API end to end with **160 assertions**:

```powershell
dotnet run --project DriveOp.Api          # in one terminal
powershell -ExecutionPolicy Bypass -File .\test-api.ps1
```

It creates two municipalities and exercises tenancy boundaries, status codes,
the incident-to-job-card transaction, the status lifecycle, delete guards,
pagination edge cases, and soft delete — asserting persisted state via separate
reads rather than trusting create responses.

Setup failures are fatal rather than skipped, because a suite that reports a
clean pass while a third of it silently didn't run is worse than one that fails.

Unit tests for the transition rules and municipality scoping are planned
alongside the auth work.

---

## Running locally

**Prerequisites:** .NET 10 SDK · SQL Server or LocalDB

```bash
git clone https://github.com/bknthejane/driveop.git
cd driveop

dotnet tool install --global dotnet-ef
dotnet restore
```

Set your connection string in `DriveOp.Api/appsettings.Development.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost;Database=DriveOp;Trusted_Connection=True;TrustServerCertificate=True"
  }
}
```

Then create the database and run:

```bash
dotnet ef database update --project DriveOp.Api
dotnet run --project DriveOp.Api
```

Swagger UI is at `/swagger`.

---

## API

Errors use [RFC 9457 `ProblemDetails`](https://datatracker.ietf.org/doc/html/rfc9457).

### Departments and work types

| Method | Route | Returns |
|---|---|---|
| `GET` | `/api/departments` | `200` — paged; filters: `municipalityId`, `search`, `unstaffed` |
| `GET` | `/api/departments/{id}` | `200`, or `404` |
| `POST` | `/api/departments` | `201` + `Location`, `400`, or `409` |
| `PUT` | `/api/departments/{id}` | `204`, `400`, `404`, or `409` |
| `DELETE` | `/api/departments/{id}` | `204`, `404`, or `409` if staffed or in use |
| `GET` | `/api/worktypes` | `200` — paged; filters: `municipalityId`, `departmentId`, `search` |
| `GET` | `/api/worktypes/{id}` | `200`, or `404` — includes the routed supervisor |
| `POST` | `/api/worktypes` | `201` + `Location`, `400`, or `409` |
| `PUT` | `/api/worktypes/{id}` | `204`, `400`, `404`, or `409` — remapping allowed within the municipality |
| `DELETE` | `/api/worktypes/{id}` | `204`, `404`, or `409` if used on an incident |

### Vehicles and drivers

| Method | Route | Returns |
|---|---|---|
| `GET` | `/api/vehicles` | `200` — paged; filters: `search`, `status`, `municipalityId` |
| `GET` | `/api/vehicles/{id}` | `200`, or `404` |
| `POST` | `/api/vehicles` | `201` + `Location`, `400`, or `409` |
| `PUT` | `/api/vehicles/{id}` | `204`, `400`, or `404` |
| `DELETE` | `/api/vehicles/{id}` | `204` or `404` — soft delete |
| `GET` | `/api/drivers` | `200` — paged and filtered |
| `GET` | `/api/drivers/{id}` | `200`, or `404` |
| `POST` | `/api/drivers` | `201` + `Location`, `400`, or `409` |
| `PUT` | `/api/drivers/{id}` | `204`, `400`, or `404` |
| `DELETE` | `/api/drivers/{id}` | `204`, `404`, or `409` if vehicles are still assigned |

### Incidents and job cards

| Method | Route | Returns |
|---|---|---|
| `GET` | `/api/incidents` | `200` — paged; filters: `vehicleId`, `driverId`, `workTypeId`, `departmentId`, `status` |
| `GET` | `/api/incidents/{id}` | `200`, or `404` |
| `POST` | `/api/incidents` | `201` + `Location`, or `400` |
| `DELETE` | `/api/incidents/{id}` | `204`, `404`, or `409` if a job card exists |
| `POST` | `/api/incidents/{id}/jobcards` | `201` + `Location`, `400`, `404`, or `409` |
| `GET` | `/api/jobcards` | `200` — paged; filters: `status`, `priority`, `municipalityId`, `assignedSupervisorId`, `assignedMechanicId`, `unassigned` |
| `GET` | `/api/jobcards/{id}` | `200`, or `404` |
| `PUT` | `/api/jobcards/{id}` | `204`, `400`, `404`, or `409` — priority and notes |
| `PUT` | `/api/jobcards/{id}/status` | `200` + updated DTO, `400`, `404`, or `409` |
| `PUT` | `/api/jobcards/{id}/assignment` | `200` + updated DTO, `400`, `404`, or `409` |

`Municipality`, `Supervisor` and `Mechanic` exist as entities but have no
endpoints yet.

Pagination is capped at 100 per page, and `page` is bounded — without an upper
bound, `(page - 1) * pageSize` overflows `int` and produces a negative `OFFSET`
that SQL Server rejects.

---

## Roadmap

- [x] **M1** — Domain model, migrations, audit and soft delete
- [x] **M2** — Vehicles CRUD, pagination, Swagger, CORS
- [x] **M3** — Drivers CRUD, incident logging, global exception handling
- [x] **M4** — JobCard generation in a transaction, status lifecycle, atomic numbering
- [ ] **M5** — Departments and routing (done), auto-created job cards, task and
      part lines, odometer, status history, approval step
- [ ] **M6** — JWT auth, role-based authorisation, municipality scoping, unit tests
- [ ] **M7** — Next.js frontend and dashboard
- [ ] **M8** — Compliance ledger (CoF, licence disc, service) and cost reporting

---

## Licence

Proprietary. All rights reserved. See [LICENSE.txt](LICENSE.txt).