# DriveOp

A fleet management system for municipalities — tracking vehicles, drivers, and the
full incident-to-repair lifecycle.

Built with ASP.NET Core, Entity Framework Core and SQL Server, with a Next.js
frontend. **Deliberately framework-free.**

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
| A 6-project solution template | Layering, which is about dependency direction — not project count |

Every architectural decision in this repo was made deliberately and is documented
below or in the commit history.

---

## Status

Actively in development. What's working today:

- ✅ Domain model — 7 entities, explicit relationship configuration, first migration
- ✅ Audit fields and soft delete via change-tracker interception
- ✅ Vehicles — full CRUD with DTOs, service layer, correct HTTP semantics
- ✅ Database-level pagination, search and filtering
- 🚧 Drivers, Incidents, JobCard workflow
- 🚧 JWT authentication and role-based authorisation
- 🚧 Next.js frontend

---

## Stack

**Backend** — ASP.NET Core 10 Web API · Entity Framework Core 10 · SQL Server
**Frontend** — Next.js (App Router) · TypeScript
**Tooling** — CodeRabbit for automated review · GitGuardian for secret scanning

---

## Domain model

```
Municipality (the tenant)
├── Vehicles ──────── assigned to ──── Driver
├── Drivers
├── Supervisors ───── oversee ──────── Mechanics
└── Mechanics

Incident (logged against a Vehicle + Driver)
└── JobCard (generated from an Incident, routed to a Supervisor/Mechanic)
```

**Core flow:** a driver logs an incident → a job card is generated → it's routed
to the right supervisor and mechanic → status cascades through the
incident-to-repair lifecycle, updating the vehicle's availability as it goes.

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
└── Common/                # ServiceResult<T>
```

Requests flow one way: **Controller → Service → DbContext → Database**, and the
mapped DTO comes back. Business logic never appears in a controller; HTTP
concerns never appear in a service.

---

## Implementation decisions

### Soft delete via change-tracker interception

`SaveChanges` is overridden to walk EF Core's change tracker before the SQL is
generated. Entries marked `Deleted` are reset to `Unchanged`, their
`IsDeleted`/`DeletedAt` fields set, and only those two properties marked as
modified — so the UPDATE touches two columns rather than every mapped property,
and a stale tracked entity can't overwrite concurrent changes.

Both `acceptAllChangesOnSuccess` overloads are overridden, not the parameterless
ones. The parameterless methods delegate to these, so guarding only those would
let some callers bypass the audit rules entirely and turn soft deletes into
physical deletes.

Global query filters (`HasQueryFilter`) then exclude soft-deleted rows from every
query automatically, including inside `Include`.

### `DeleteBehavior.Restrict` on every relationship

Soft delete means `IsDeleted = true` is an **UPDATE**, so a foreign key
constraint never fires. Configuring `Cascade` would be decorative — it would
never run, while leaving orphaned children pointing at a hidden parent.

`Restrict` instead acts as a genuine safety net against anything that bypasses
the soft-delete path: a manual SQL script, a seeding bug, `ExecuteDeleteAsync`.
Cascading a soft delete is then an explicit, transactional decision in the
service layer.

It also avoids SQL Server's multiple-cascade-path restriction: `Vehicle` reaches
`Municipality` both directly and via `AssignedDriver`, and `Mechanic` reaches it
both directly and via `Supervisor`.

### DTOs at every boundary

Entities are never exposed. Each operation gets its own shape:

- `CreateVehicleDto` has no `Id` or audit fields — a client physically cannot
  set them, so over-posting is structurally impossible rather than
  runtime-checked
- `UpdateVehicleDto` omits `FleetNumber` and `MunicipalityId` — both are treated
  as immutable after creation; transferring a vehicle between municipalities is
  a distinct operation with its own rules
- `VehicleListDto` is a lighter shape, so list queries select fewer columns

### Projection over eager loading on lists

List endpoints project inside `IQueryable` rather than calling `Include` and
mapping afterwards. `Include` emits a `LEFT JOIN` returning every column of every
joined table; projection selects only the columns the DTO needs.

The generated SQL also pushes `OFFSET/FETCH` into a subquery so the join runs
against the current page rather than the full result set.

### Services return results, not HTTP types

`ServiceResult<T>` carries a success flag, a value, and an error type
(`NotFound`, `Conflict`, `Validation`). The controller maps error types to status
codes in one place. The service layer has no dependency on ASP.NET Core, so it's
testable without a web host and reusable from a background job.

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

| Method | Route | Returns |
|---|---|---|
| `GET` | `/api/vehicles` | `200` — paged, filterable list |
| `GET` | `/api/vehicles/{id}` | `200`, or `404` |
| `POST` | `/api/vehicles` | `201` + `Location` header, `400`, or `409` |
| `PUT` | `/api/vehicles/{id}` | `204`, `400`, or `404` |
| `DELETE` | `/api/vehicles/{id}` | `204` or `404` — soft delete |

Query parameters on the list endpoint: `page`, `pageSize` (capped at 100),
`search`, `status`, `municipalityId`.

Errors use [RFC 9457 `ProblemDetails`](https://datatracker.ietf.org/doc/html/rfc9457).

---

## Roadmap

- [x] **M1** — Domain model, migrations, audit and soft delete
- [x] **M2** — Vehicles CRUD, pagination, Swagger, CORS
- [ ] **M3** — Drivers CRUD, incident logging, global exception handling, seeding
- [ ] **M4** — JobCard generation and status lifecycle, in a transaction
- [ ] **M5** — JWT auth, role-based authorisation, municipality scoping, unit tests
- [ ] **M6** — Next.js frontend and dashboard

---

## Licence

Proprietary. All rights reserved. See [LICENSE.txt](LICENSE.txt).