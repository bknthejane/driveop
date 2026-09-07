using DriveOp.Api.Common;
using DriveOp.Api.Data;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Drivers;
using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace DriveOp.Api.Services.Drivers
{
    public class DriverService : IDriverService
    {
        private readonly DriveOpDbContext _context;

        public DriverService(DriveOpDbContext context)
        {
            _context = context;
        }

        public async Task<PagedResult<DriverListDto>> GetAllAsync(DriverQueryParameters parameters, CancellationToken cancellationToken)
        {
            var query = _context.Drivers.AsNoTracking();

            if (!string.IsNullOrWhiteSpace(parameters.Search))
            {
                var search = parameters.Search.Trim();
                query = query.Where(d =>
                    EF.Functions.Like(d.Name, $"%{search}%") ||
                    EF.Functions.Like(d.Surname, $"%{search}%") ||
                    EF.Functions.Like(d.LicenseNumber, $"%{search}%"));
            }

            if (parameters.MunicipalityId.HasValue)
                query = query.Where(d => d.MunicipalityId == parameters.MunicipalityId.Value);

            var totalCount = await query.CountAsync(cancellationToken);

            var items = await query
                .OrderBy(d => d.Name)
                .ThenBy(d => d.Id)
                .Skip((parameters.Page - 1) * parameters.PageSize)
                .Take(parameters.PageSize)
                .Select(d => new DriverListDto
                {
                    Id = d.Id,
                    Name = d.Name,
                    Surname = d.Surname,
                    LicenseNumber = d.LicenseNumber
                })
                .ToListAsync(cancellationToken);

            return new PagedResult<DriverListDto>
            {
                Items = items,
                Page = parameters.Page,
                PageSize = parameters.PageSize,
                TotalCount = totalCount
            };
        }

        public async Task<ServiceResult<DriverDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken)
        {
            var driver = await _context.Drivers
                .AsNoTracking()
                .Include(d => d.Municipality)
                .Include(d => d.AssignedVehicles)
                .FirstOrDefaultAsync(d => d.Id == id, cancellationToken);

            if (driver is null)
                return ServiceResult<DriverDto>.NotFound($"Driver {id} was not found.");

            return ServiceResult<DriverDto>.Success(MapToDto(driver));
        }

        public async Task<ServiceResult<DriverDto>> CreateAsync(CreateDriverDto dto, CancellationToken cancellationToken)
        {
            var licenseNumberTaken = await _context.Drivers
                .AnyAsync(d => d.LicenseNumber == dto.LicenseNumber, cancellationToken);

            if (licenseNumberTaken)
                return ServiceResult<DriverDto>.Conflict($"License Number '{dto.LicenseNumber}' already exists.");

            var municipalityExists = await _context.Municipalities
                .AnyAsync(m => m.Id == dto.MunicipalityId, cancellationToken);

            if (!municipalityExists)
                return ServiceResult<DriverDto>.Validation($"Municipality {dto.MunicipalityId} was not found.");

            var driver = new Driver
            {
                Id = Guid.NewGuid(),
                Name = dto.Name,
                Surname = dto.Surname,
                LicenseNumber = dto.LicenseNumber,
                MunicipalityId = dto.MunicipalityId,
            };

            _context.Drivers.Add(driver);

            try
            {
                await _context.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateException)
            {
                return ServiceResult<DriverDto>.Conflict($"License Number '{dto.LicenseNumber}' already exists.");
            }

            return await GetByIdAsync(driver.Id, cancellationToken);
        }

        public async Task<ServiceResult<DriverDto>> UpdateAsync(Guid id, UpdateDriverDto dto, CancellationToken cancellationToken)
        {
            var driver = await _context.Drivers
                .FirstOrDefaultAsync(d => d.Id == id, cancellationToken);

            if (driver is null)
                return ServiceResult<DriverDto>.NotFound($"Driver {id} was not found.");

            driver.Name = dto.Name;
            driver.Surname = dto.Surname;
            driver.LicenseNumber = dto.LicenseNumber;

            await _context.SaveChangesAsync(cancellationToken);

            return await GetByIdAsync(id, cancellationToken);
        }

        public async Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken)
        {
            var driver = await _context.Drivers
                .FirstOrDefaultAsync(d => d.Id == id, cancellationToken);

            if (driver is null)
                return ServiceResult<bool>.NotFound($"Vehicle {id} was not found.");

            var assignedVehicles = await _context.Vehicles
                .Where(v => v.AssignedDriverId == id)
                .Select(v => v.FleetNumber)
                .ToListAsync(cancellationToken);

            if (assignedVehicles.Count > 0)
            {
                return ServiceResult<bool>.Conflict(
                    $"This driver is still assigned to {assignedVehicles.Count} vehicle(s): " +
                    $"{string.Join(",", assignedVehicles)}. Unassign them before deleting the driver.");
            }

            _context.Drivers.Remove(driver);
            await _context.SaveChangesAsync(cancellationToken);

            return ServiceResult<bool>.Success(true);
        }

        private static DriverDto MapToDto(Driver driver) => new()
        {
            Id = driver.Id,
            Name = driver.Name,
            Surname = driver.Surname,
            LicenseNumber = driver.LicenseNumber,
            MunicipalityId = driver.MunicipalityId,
            MunicipalityName = driver.Municipality.Name,
            CreatedAt = driver.CreatedAt,
            UpdatedAt = driver.UpdatedAt
        };
    }
}
