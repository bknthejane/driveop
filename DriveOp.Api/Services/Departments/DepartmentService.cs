using DriveOp.Api.Common;
using DriveOp.Api.Data;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Departments;
using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace DriveOp.Api.Services.Departments
{
    public class DepartmentService : IDepartmentService
    {
        private readonly DriveOpDbContext _context;

        public DepartmentService(DriveOpDbContext context)
        {
            _context = context;
        }

        public async Task<PagedResult<DepartmentListDto>> GetAllAsync(DepartmentQueryParameters parameters, CancellationToken cancellationToken)
        {
            var query = _context.Departments.AsNoTracking();

            if (parameters.MunicipalityId.HasValue)
                query = query.Where(d => d.MunicipalityId == parameters.MunicipalityId.Value);

            if (!string.IsNullOrWhiteSpace(parameters.Search))
            {
                var search = parameters.Search.Trim();
                query = query.Where(d => EF.Functions.Like(d.Name, $"%{search}%"));
            }

            if (parameters.Unstaffed == true)
                query = query.Where(d => d.Supervisor == null);

            var totalCount = await query.CountAsync(cancellationToken);

            var items = await query
                .OrderBy(d => d.Name)
                .ThenBy(d => d.Id)
                .Skip(parameters.Skip)
                .Take(parameters.PageSize)
                .Select(d => new DepartmentListDto
                {
                    Id = d.Id,
                    Name = d.Name,
                    SupervisorName = d.Supervisor == null
                        ? null
                        : d.Supervisor.Name + " " + d.Supervisor.Surname,
                    WorkTypeCount = d.WorkTypes.Count,
                    MechanicCount = d.Mechanics.Count
                })
                .ToListAsync(cancellationToken);

            return new PagedResult<DepartmentListDto>
            {
                Items = items,
                Page = parameters.Page,
                PageSize = parameters.PageSize,
                TotalCount = totalCount
            };
        }

        public async Task<ServiceResult<DepartmentDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken)
        {
            var department = await _context.Departments
                .AsNoTracking()
                .Where(d => d.Id == id)
                .Select(d => new DepartmentDto
                {
                    Id = d.Id,
                    Name = d.Name,
                    Description = d.Description,
                    MunicipalityId = d.MunicipalityId,
                    MunicipalityName = d.Municipality.Name,
                    SupervisorId = d.Supervisor == null ? null : d.Supervisor.Id,
                    SupervisorName = d.Supervisor == null
                        ? null
                        : d.Supervisor.Name + " " + d.Supervisor.Surname,
                    WorkTypeCount = d.WorkTypes.Count,
                    MechanicCount = d.Mechanics.Count,
                    CreatedAt = d.CreatedAt,
                    UpdatedAt = d.UpdatedAt
                })
                .FirstOrDefaultAsync(cancellationToken);

            return department is null
                ? ServiceResult<DepartmentDto>.NotFound($"Department {id} was not found.")
                : ServiceResult<DepartmentDto>.Success(department);
        }

        public async Task<ServiceResult<DepartmentDto>> CreateAsync(CreateDepartmentDto dto, CancellationToken cancellationToken)
        {
            var municipalityExists = await _context.Municipalities
                .AnyAsync(m => m.Id == dto.MunicipalityId, cancellationToken);

            if (!municipalityExists)
                return ServiceResult<DepartmentDto>.Validation(
                    $"Municipality {dto.MunicipalityId} was not found.");

            var name = dto.Name.Trim();

            var nameTaken = await _context.Departments
                .AnyAsync(d => d.MunicipalityId == dto.MunicipalityId
                            && d.Name == name, cancellationToken);

            if (nameTaken)
                return ServiceResult<DepartmentDto>.Conflict(
                    $"A department named '{name}' already exists in this municipality.");

            var department = new Department
            {
                Id = Guid.NewGuid(),
                Name = name,
                Description = dto.Description?.Trim(),
                MunicipalityId = dto.MunicipalityId
            };

            _context.Departments.Add(department);
            await _context.SaveChangesAsync(cancellationToken);

            return await GetByIdAsync(department.Id, cancellationToken);
        }

        public async Task<ServiceResult<bool>> UpdateAsync(Guid id, UpdateDepartmentDto dto, CancellationToken cancellationToken)
        {
            var department = await _context.Departments
                .FirstOrDefaultAsync(d => d.Id == id, cancellationToken);

            if (department is null)
                return ServiceResult<bool>.NotFound($"Department {id} was not found.");

            var name = dto.Name.Trim();

            var nameTaken = await _context.Departments
                .AnyAsync(d => d.MunicipalityId == department.MunicipalityId
                            && d.Name == name
                            && d.Id != id, cancellationToken);

            if (nameTaken)
                return ServiceResult<bool>.Conflict(
                    $"A department named '{name}' already exists in this municipality.");

            department.Name = name;
            department.Description = dto.Description?.Trim();

            try
            {
                await _context.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateConcurrencyException)
            {
                return ServiceResult<bool>.Conflict(
                    "This department was changed by someone else. Reload and try again.");
            }

            return ServiceResult<bool>.Success(true);
        }

        public async Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken)
        {
            var department = await _context.Departments
                .FirstOrDefaultAsync(d => d.Id == id, cancellationToken);

            if (department is null)
                return ServiceResult<bool>.NotFound($"Department {id} was not found.");

            var hasSupervisor = await _context.Supervisors
                .AnyAsync(s => s.DepartmentId == id, cancellationToken);

            if (hasSupervisor)
                return ServiceResult<bool>.Conflict(
                    "This department has a supercisor. Reassign or remove the supervisor first.");

            var workTypeNames = await _context.WorkTypes
                .Where(w => w.DepartmentId == id)
                .Select(w => w.Name)
                .Take(10)
                .ToListAsync(cancellationToken);

            if (workTypeNames.Count > 0)
                return ServiceResult<bool>.Conflict(
                    $"This department has work types assigned to it: " +
                    $"{string.Join(", ", workTypeNames)}. Remap or remove them first.");

            var mechanicCount = await _context.Mechanics
                .CountAsync(m => m.DepartmentId == id, cancellationToken);

            if (mechanicCount > 0)
                return ServiceResult<bool>.Conflict(
                    $"This department has {mechanicCount} mechanic(s) assigned to it. " +
                    "Reassign them first.");

            _context.Departments.Remove(department);
            await _context.SaveChangesAsync(cancellationToken);

            return ServiceResult<bool>.Success(true);
        }
    }
}
