using DriveOp.Api.Common;
using DriveOp.Api.Data;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Incidents;
using DriveOp.Api.Entities;
using DriveOp.Api.Entities.Enums;
using Microsoft.EntityFrameworkCore;

namespace DriveOp.Api.Services.Incidents
{
    public class IncidentService : IIncidentService
    {
        private readonly DriveOpDbContext _context;

        public IncidentService(DriveOpDbContext context)
        {
            _context = context;
        }

        public async Task<PagedResult<IncidentListDto>> GetAllAsync(IncidentQueryParameters parameters, CancellationToken cancellationToken)
        {
            var query = _context.Incidents.AsNoTracking();

            if (parameters.VehicleId.HasValue)
                query = query.Where(i => i.VehicleId == parameters.VehicleId.Value);

            if (parameters.DriverId.HasValue)
                query = query.Where(i => i.DriverId == parameters.DriverId.Value);

            if (parameters.MunicipalityId.HasValue)
                query = query.Where(i => i.Vehicle.MunicipalityId == parameters.MunicipalityId.Value);

            if (parameters.Status.HasValue)
                query = query.Where(i => i.Status == parameters.Status.Value);

            if (parameters.WorkTypeId.HasValue)
                query = query.Where(i => i.WorkTypeId == parameters.WorkTypeId.Value);

            if (parameters.DepartmentId.HasValue)
                query = query.Where(i => i.DepartmentId == parameters.DepartmentId.Value);

            var totalCount = await query.CountAsync(cancellationToken);

            var items = await query
                .OrderByDescending(i => i.DateReported)
                .ThenBy(i => i.Id)
                .Skip(parameters.Skip)
                .Take(parameters.PageSize)
                .Select(i => new IncidentListDto
                {
                    Id = i.Id,
                    WorkTypeName = i.WorkType.Name,
                    DepartmentName = i.Department.Name,
                    Status = i.Status,
                    DateReported = i.DateReported,
                    VehicleFleetNumber = i.Vehicle.FleetNumber,
                    DriverName = i.Driver.Name + " " + i.Driver.Surname,
                    HasJobCard = i.JobCard != null
                })
                .ToListAsync(cancellationToken);

            return new PagedResult<IncidentListDto>
            {
                Items = items,
                Page = parameters.Page,
                PageSize = parameters.PageSize,
                TotalCount = totalCount
            };
        }

        public async Task<ServiceResult<IncidentDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken)
        {
            var incident = await _context.Incidents
                .AsNoTracking()
                .Where(i => i.Id == id)
                .Select(i => new IncidentDto
                {
                    Id = i.Id,
                    Description = i.Description,
                    WorkTypeId = i.WorkTypeId,
                    WorkTypeName = i.WorkType.Name,
                    DepartmentId = i.DepartmentId,
                    DepartmentName = i.Department.Name,
                    Status = i.Status,
                    DateReported = i.DateReported,
                    VehicleId = i.VehicleId,
                    VehicleFleetNumber = i.Vehicle.FleetNumber,
                    VehicleRegistrationNumber = i.Vehicle.RegistrationNumber,
                    DriverId = i.DriverId,
                    DriverName = i.Driver.Name + " " + i.Driver.Surname,
                    MunicipalityId = i.Vehicle.MunicipalityId,
                    MunicipalityName = i.Vehicle.Municipality.Name,
                    HasJobCard = i.JobCard != null,
                    CreatedAt = i.CreatedAt,
                    UpdatedAt = i.UpdatedAt
                })
                .FirstOrDefaultAsync(cancellationToken);

            return incident is null
                ? ServiceResult<IncidentDto>.NotFound($"Incident {id} was not found.")
                : ServiceResult<IncidentDto>.Success(incident);
        }

        public async Task<ServiceResult<IncidentDto>> CreateAsync(CreateIncidentDto dto, CancellationToken cancellationToken)
        {
            var workType = await _context.WorkTypes
                .AsNoTracking()
                .Where(w => w.Id == dto.WorkTypeId)
                .Select(w => new { w.Id, w.MunicipalityId, w.DepartmentId })
                .FirstOrDefaultAsync(cancellationToken);

            if (workType is null)
                return ServiceResult<IncidentDto>.Validation($"Work type {dto.WorkTypeId} was not found.");

            var vehicle = await _context.Vehicles
                 .AsNoTracking()
                 .Where(v => v.Id == dto.VehicleId)
                 .Select(v => new { v.Id, v.MunicipalityId, v.Status })
                 .FirstOrDefaultAsync(cancellationToken);

            if (vehicle is null)
                return ServiceResult<IncidentDto>.Validation($"Vehicle {dto.VehicleId} was not found.");

            var driver = await _context.Drivers
                .AsNoTracking()
                .Where(d => d.Id == dto.DriverId)
                .Select(d => new { d.Id, d.MunicipalityId })
                .FirstOrDefaultAsync(cancellationToken);

            if (driver is null)
                return ServiceResult<IncidentDto>.Validation($"Driver {dto.DriverId} was not found.");

            if (vehicle.MunicipalityId != driver.MunicipalityId)
                return ServiceResult<IncidentDto>.Validation(
                    "The vehicle and driver must belong to the same municipality.");

            if (vehicle.Status == VehicleStatus.Decommissioned)
                return ServiceResult<IncidentDto>.Validation(
                    "An incident cannot be logged against a decommissioned vehicle.");

            if (workType.MunicipalityId != vehicle.MunicipalityId)
                return ServiceResult<IncidentDto>.Validation(
                    "The work type must belong to the same municipality as the vehicle.");

            var incident = new Incident
            {
                Id = Guid.NewGuid(),
                Description = dto.Description,
                WorkTypeId = workType.Id,
                DepartmentId = workType.DepartmentId,
                Status = IncidentStatus.Reported,
                DateReported = DateTime.UtcNow,
                VehicleId = dto.VehicleId,
                DriverId = dto.DriverId
            };

            _context.Incidents.Add(incident);
            await _context.SaveChangesAsync(cancellationToken);

            return await GetByIdAsync(incident.Id, cancellationToken);
            
        }

        public async Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken)
        {
            var incident = await _context.Incidents
                .FirstOrDefaultAsync(i => i.Id == id, cancellationToken);

            if (incident is null)
                return ServiceResult<bool>.NotFound($"Incident {id} was not found.");

            var hasJobCard = await _context.JobCards
                .AnyAsync(j => j.IncidentId == id, cancellationToken);

            if (hasJobCard)
                return ServiceResult<bool>.Conflict(
                    "This incident has a job card. Delete or cancel the job card before deleting the incident.");

            _context.Incidents.Remove(incident);
            await _context.SaveChangesAsync(cancellationToken);

            return ServiceResult<bool>.Success(true);
        }
    }
}
