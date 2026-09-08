using DriveOp.Api.Common;
using DriveOp.Api.Data;
using DriveOp.Api.DTOs.JobCards;
using DriveOp.Api.Entities;
using DriveOp.Api.Entities.Enums;
using Microsoft.EntityFrameworkCore;

namespace DriveOp.Api.Services.JobCards
{
    public class JobCardService : IJobCardService
    {
        private readonly DriveOpDbContext _context;

        public JobCardService(DriveOpDbContext context)
        {
            _context = context;
        }

        public async Task<ServiceResult<JobCardDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken)
        {
            var jobCard = await _context.JobCards
                .AsNoTracking()
                .Where(j => j.Id == id)
                .Select(j => new JobCardDto
                {
                    Id = j.Id,
                    JobCardNumber = j.JobCardNumber,
                    Status = j.Status,
                    Priority = j.Priority,
                    Notes = j.Notes,
                    DateOpened = j.DateOpened,
                    DateCompleted = j.DateCompleted,
                    IncidentId = j.IncidentId,
                    IncidentDescription = j.Incident.Description,
                    IncidentStatus = j.Incident.Status,
                    VehicleId = j.Incident.VehicleId,
                    VehicleFleetNumber = j.Incident.Vehicle.FleetNumber,
                    VehicleStatus = j.Incident.Vehicle.Status,
                    MunicipalityId = j.MunicipalityId,
                    MunicipalityName = j.Municipality.Name,
                    AssignedSupervisorId = j.AssignedSupervisorId,
                    AssignedSupervisorName = j.AssignedSupervisor == null ? null : j.AssignedSupervisor.Name + " " + j.AssignedSupervisor.Surname,
                    AssignedMechanicId = j.AssignedMechanicId,
                    AssignedMechanicName = j.AssignedMechanic == null ? null : j.AssignedMechanic.Name + " " + j.AssignedMechanic.Surname,
                    CreatedAt = j.CreatedAt,
                    UpdatedAt = j.UpdatedAt
                })
                .FirstOrDefaultAsync(cancellationToken);

            return jobCard is null ? ServiceResult<JobCardDto>.NotFound($"Job card {id} was not found.") : ServiceResult<JobCardDto>.Success(jobCard);
        }

        public async Task<ServiceResult<JobCardDto>> CreateFromIncidentAsync(Guid incidentId, CreateJobCardDto dto, CancellationToken cancellationToken)
        {
            if (!Enum.IsDefined(dto.Priority))
                return ServiceResult<JobCardDto>.Validation(
                    $"'{(int)dto.Priority}' is not a valid priority.");

            var incident = await _context.Incidents
                .Include(i => i.Vehicle)
                .FirstOrDefaultAsync(i => i.Id == incidentId, cancellationToken);

            if (incident is null)
                return ServiceResult<JobCardDto>.NotFound($"Incident {incidentId} was not found.");

            if (incident.Status == IncidentStatus.Resolved)
                return ServiceResult<JobCardDto>.Conflict(
                    "A job card cannot be created for a resolved incident.");

            var alreadyHasJobCard = await _context.JobCards
                .AnyAsync(j => j.IncidentId == incidentId, cancellationToken);

            if (alreadyHasJobCard)
                return ServiceResult<JobCardDto>.Conflict("This incident already has a job card");

            var municipalityId = incident.Vehicle.MunicipalityId;

            if (dto.AssignedSupervisorId.HasValue)
            {
                var supervisorIsValid = await _context.Supervisors
                    .AnyAsync(s => s.Id == dto.AssignedSupervisorId.Value
                                && s.MunicipalityId == municipalityId, cancellationToken);

                if (!supervisorIsValid)
                    return ServiceResult<JobCardDto>.Validation(
                        "The assigned supervisor must belong to the incident's municipality.");
            }

            if (dto.AssignedMechanicId.HasValue)
            {
                var mechanicIsValid = await _context.Mechanics
                    .AnyAsync(m => m.Id == dto.AssignedMechanicId.Value
                                && m.MunicipalityId == municipalityId, cancellationToken);

                if (!mechanicIsValid)
                    return ServiceResult<JobCardDto>.Validation(
                        "The assigned mechanic must belong to the incident's municipality.");
            }

            await using var transaction = await _context.Database.BeginTransactionAsync(cancellationToken);

            try
            {
                var jobCard = new JobCard
                {
                    Id = Guid.NewGuid(),
                    JobCardNumber = await GenerateJobCardNumberAsync(municipalityId, cancellationToken),
                    Status = JobCardStatus.Open,
                    Priority = dto.Priority,
                    Notes = dto.Notes,
                    DateOpened = DateTime.UtcNow,
                    IncidentId = incident.Id,
                    MunicipalityId = municipalityId,
                    AssignedSupervisorId = dto.AssignedSupervisorId,
                    AssignedMechanicId = dto.AssignedMechanicId
                };

                _context.JobCards.Add(jobCard);

                incident.Status = IncidentStatus.JobCardCreated;
                incident.Vehicle.Status = VehicleStatus.UnderRepair;

                await _context.SaveChangesAsync(cancellationToken);
                await transaction.CommitAsync(cancellationToken);

                return await GetByIdAsync(jobCard.Id, cancellationToken);
            }
            catch
            {
                await transaction.RollbackAsync(cancellationToken);
                throw;
            }

        }

        public async Task<ServiceResult<JobCardDto>> UpdateStatusAsync(Guid id, UpdateJobCardStatusDto dto, CancellationToken cancellationToken)
        {
            if (!Enum.IsDefined(dto.Status))
                return ServiceResult<JobCardDto>.Validation(
                    $"'{(int)dto.Status}' is not a valid job card status.");

            var jobCard = await _context.JobCards
                .Include(j => j.Incident)
                    .ThenInclude(i => i.Vehicle)
                .FirstOrDefaultAsync(j => j.Id == id, cancellationToken);

            if (jobCard is null)
                return ServiceResult<JobCardDto>.NotFound($"Job card {id} was not found.");

            if (!JobCardStatusTransactions.IsAllowed(jobCard.Status, dto.Status))
            {
                var allowed = JobCardStatusTransactions.AllowedFrom(jobCard.Status);

                var detail = allowed.Count == 0
                    ? $"A job card in status {jobCard.Status} is final and cannot be changed."
                    : $"Cannot move a job card from {jobCard.Status} to {dto.Status}." +
                    $"Allowed: {string.Join(", ", allowed)}.";

                return ServiceResult<JobCardDto>.Conflict(detail);
            }

            await using var transaction = await _context.Database
                .BeginTransactionAsync(cancellationToken);

            try
            {
                jobCard.Status = dto.Status;

                if (dto.Notes is not null)
                    jobCard.Notes = dto.Notes;

                switch (dto.Status)
                {
                    case JobCardStatus.InProgress:
                        jobCard.Incident.Vehicle.Status = VehicleStatus.UnderRepair;
                        break;

                    case JobCardStatus.Completed:
                        jobCard.DateCompleted = DateTime.UtcNow;
                        jobCard.Incident.Status = IncidentStatus.Resolved;
                        jobCard.Incident.Vehicle.Status = VehicleStatus.Active;
                        break;

                    case JobCardStatus.Cancelled:
                        jobCard.Incident.Status = IncidentStatus.Acknowledged;
                        jobCard.Incident.Vehicle.Status = VehicleStatus.Active;
                        break;
                }

                await _context.SaveChangesAsync(cancellationToken);
                await transaction.CommitAsync(cancellationToken);

                return await GetByIdAsync(id, cancellationToken);
            }
            catch
            {
                await transaction.RollbackAsync(cancellationToken);
                throw;
            }
        }

        private async Task<string> GenerateJobCardNumberAsync(Guid municipalityId, CancellationToken cancellationToken)
        {
            var prefix = $"JC-{DateTime.UtcNow:yyyyMMdd}-";

            var lastNumber = await _context.JobCards
                .IgnoreQueryFilters()
                .Where(j => j.MunicipalityId == municipalityId
                         && j.JobCardNumber.StartsWith(prefix))
                .OrderByDescending(j => j.JobCardNumber)
                .Select(j => j.JobCardNumber)
                .FirstOrDefaultAsync(cancellationToken);

            var next = 1;

            if (lastNumber is not null && int.TryParse(lastNumber.Substring(prefix.Length), out var parsed))
            {
                next = parsed + 1;
            }

            return $"{prefix}{next:D3}";
        }
    }
}
