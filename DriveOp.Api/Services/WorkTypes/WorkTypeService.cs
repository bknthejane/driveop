using DriveOp.Api.Common;
using DriveOp.Api.Data;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.WorkTypes;
using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace DriveOp.Api.Services.WorkTypes
{
    public class WorkTypeService : IWorkTypeService
    {
        private readonly DriveOpDbContext _context;

        public WorkTypeService(DriveOpDbContext context)
        {
            _context = context;
        }

        public async Task<PagedResult<WorkTypeListDto>> GetAllAsync(
            WorkTypeQueryParameters parameters, CancellationToken cancellationToken)
        {
            var query = _context.WorkTypes.AsNoTracking();

            if (parameters.MunicipalityId.HasValue)
                query = query.Where(w => w.MunicipalityId == parameters.MunicipalityId.Value);

            if (parameters.DepartmentId.HasValue)
                query = query.Where(w => w.DepartmentId == parameters.DepartmentId.Value);

            if (!string.IsNullOrWhiteSpace(parameters.Search))
            {
                var search = parameters.Search.Trim();
                query = query.Where(w => EF.Functions.Like(w.Name, $"%{search}%"));
            }

            var totalCount = await query.CountAsync(cancellationToken);

            var items = await query
                .OrderBy(w => w.Department.Name)
                .ThenBy(w => w.Name)
                .ThenBy(w => w.Id)
                .Skip(parameters.Skip)
                .Take(parameters.PageSize)
                .Select(w => new WorkTypeListDto
                {
                    Id = w.Id,
                    Name = w.Name,
                    DepartmentName = w.Department.Name,
                    SupervisorName = w.Department.Supervisor == null
                        ? null
                        : w.Department.Supervisor.Name + " " + w.Department.Supervisor.Surname
                })
                .ToListAsync(cancellationToken);

            return new PagedResult<WorkTypeListDto>
            {
                Items = items,
                Page = parameters.Page,
                PageSize = parameters.PageSize,
                TotalCount = totalCount
            };
        }

        public async Task<ServiceResult<WorkTypeDto>> GetByIdAsync(
            Guid id, CancellationToken cancellationToken)
        {
            var workType = await _context.WorkTypes
                .AsNoTracking()
                .Where(w => w.Id == id)
                .Select(w => new WorkTypeDto
                {
                    Id = w.Id,
                    Name = w.Name,
                    DepartmentId = w.DepartmentId,
                    DepartmentName = w.Department.Name,
                    MunicipalityId = w.MunicipalityId,
                    MunicipalityName = w.Municipality.Name,
                    SupervisorId = w.Department.Supervisor == null
                        ? null
                        : w.Department.Supervisor.Id,
                    SupervisorName = w.Department.Supervisor == null
                        ? null
                        : w.Department.Supervisor.Name + " " + w.Department.Supervisor.Surname,
                    CreatedAt = w.CreatedAt,
                    UpdatedAt = w.UpdatedAt
                })
                .FirstOrDefaultAsync(cancellationToken);

            return workType is null
                ? ServiceResult<WorkTypeDto>.NotFound($"Work type {id} was not found.")
                : ServiceResult<WorkTypeDto>.Success(workType);
        }

        public async Task<ServiceResult<WorkTypeDto>> CreateAsync(
            CreateWorkTypeDto dto, CancellationToken cancellationToken)
        {
            var department = await _context.Departments
                .AsNoTracking()
                .Where(d => d.Id == dto.DepartmentId)
                .Select(d => new { d.Id, d.MunicipalityId })
                .FirstOrDefaultAsync(cancellationToken);

            if (department is null)
                return ServiceResult<WorkTypeDto>.Validation(
                    $"Department {dto.DepartmentId} was not found.");

            var name = dto.Name.Trim();

            var nameTaken = await _context.WorkTypes
                .AnyAsync(w => w.MunicipalityId == department.MunicipalityId
                            && w.Name == name, cancellationToken);

            if (nameTaken)
                return ServiceResult<WorkTypeDto>.Conflict(
                    $"A work type named '{name}' already exists in this municipality.");

            var workType = new WorkType
            {
                Id = Guid.NewGuid(),
                Name = name,
                DepartmentId = department.Id,
                MunicipalityId = department.MunicipalityId
            };

            _context.WorkTypes.Add(workType);
            await _context.SaveChangesAsync(cancellationToken);

            return await GetByIdAsync(workType.Id, cancellationToken);
        }

        public async Task<ServiceResult<bool>> UpdateAsync(
            Guid id, UpdateWorkTypeDto dto, CancellationToken cancellationToken)
        {
            var workType = await _context.WorkTypes
                .FirstOrDefaultAsync(w => w.Id == id, cancellationToken);

            if (workType is null)
                return ServiceResult<bool>.NotFound($"Work type {id} was not found.");

            var department = await _context.Departments
                .AsNoTracking()
                .Where(d => d.Id == dto.DepartmentId)
                .Select(d => new { d.Id, d.MunicipalityId })
                .FirstOrDefaultAsync(cancellationToken);

            if (department is null)
                return ServiceResult<bool>.Validation(
                    $"Department {dto.DepartmentId} was not found.");

            if (department.MunicipalityId != workType.MunicipalityId)
                return ServiceResult<bool>.Validation(
                    "A work type cannot be remapped to a department in another municipality.");

            var name = dto.Name.Trim();

            var nameTaken = await _context.WorkTypes
                .AnyAsync(w => w.MunicipalityId == workType.MunicipalityId
                            && w.Name == name
                            && w.Id != id, cancellationToken);

            if (nameTaken)
                return ServiceResult<bool>.Conflict(
                    $"A work type named '{name}' already exists in this municipality.");

            workType.Name = name;
            workType.DepartmentId = department.Id;

            try
            {
                await _context.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateConcurrencyException)
            {
                return ServiceResult<bool>.Conflict(
                    "This work type was changed by someone else. Reload and try again.");
            }

            return ServiceResult<bool>.Success(true);
        }

        public async Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken)
        {
            var workType = await _context.WorkTypes
                .FirstOrDefaultAsync(w => w.Id == id, cancellationToken);

            if (workType is null)
                return ServiceResult<bool>.NotFound($"Work type {id} was not found.");

            var incidentCount = await _context.Incidents
                .CountAsync(i => i.WorkTypeId == id, cancellationToken);

            if (incidentCount > 0)
                return ServiceResult<bool>.Conflict(
                    $"This work type has been used on {incidentCount} incident(s) and is " +
                    "retained as history. It cannot be deleted.");

            _context.WorkTypes.Remove(workType);
            await _context.SaveChangesAsync(cancellationToken);

            return ServiceResult<bool>.Success(true);
        }
    }
}
