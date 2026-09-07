using DriveOp.Api.Common;
using DriveOp.Api.Data;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Vehicles;
using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace DriveOp.Api.Services.Vehicles
{
    public class VehicleService : IVehicleService
    {
        private readonly DriveOpDbContext _context;

        public VehicleService(DriveOpDbContext context)
        {
            _context = context;
        }

        public async Task<PagedResult<VehicleListDto>> GetAllAsync(VehicleQueryParameters parameters, CancellationToken cancellationToken)
        {
            var query = _context.Vehicles.AsNoTracking();

            if (!string.IsNullOrWhiteSpace(parameters.Search))
            {
                var search = parameters.Search.Trim();
                query = query.Where(v =>
                    EF.Functions.Like(v.FleetNumber, $"%{search}%") ||
                    EF.Functions.Like(v.RegistrationNumber, $"%{search}%") ||
                    EF.Functions.Like(v.Make, $"%{search}%") ||
                    EF.Functions.Like(v.Model, $"%{search}%"));
            }

            if (parameters.Status.HasValue)
                query = query.Where(v => v.Status == parameters.Status.Value);

            if (parameters.MunicipalityId.HasValue)
                query = query.Where(v => v.MunicipalityId == parameters.MunicipalityId.Value);

            var totalCount = await query.CountAsync(cancellationToken);

            var items = await query
                .OrderBy(v => v.FleetNumber)
                .ThenBy(v => v.Id)
                .Skip((parameters.Page - 1) * parameters.PageSize)
                .Take(parameters.PageSize)
                .Select(v => new VehicleListDto
                {
                    Id = v.Id,
                    FleetNumber = v.FleetNumber,
                    RegistrationNumber = v.RegistrationNumber,
                    Make = v.Make,
                    Model = v.Model,
                    Status = v.Status,
                    AssignedDriverName = v.AssignedDriver == null
                        ? null
                        : v.AssignedDriver.Name + " " + v.AssignedDriver.Surname
                })
                .ToListAsync(cancellationToken);

            return new PagedResult<VehicleListDto>
            {
                Items = items,
                Page = parameters.Page,
                PageSize = parameters.PageSize,
                TotalCount = totalCount
            };
        }

        public async Task<ServiceResult<VehicleDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken)
        {
            var vehicle = await _context.Vehicles
                .AsNoTracking()
                .Include(v => v.Municipality)
                .Include(v => v.AssignedDriver)
                .FirstOrDefaultAsync(v => v.Id == id, cancellationToken);

            if (vehicle is null)
                return ServiceResult<VehicleDto>.NotFound($"Vehicle {id} was not found.");

            return ServiceResult<VehicleDto>.Success(MapToDto(vehicle));
        }

        public async Task<ServiceResult<VehicleDto>> CreateAsync(CreateVehicleDto dto, CancellationToken cancellationToken)
        {
            if (dto.LicenseExpiry is null || dto.LicenseExpiry == DateOnly.MinValue)
                return ServiceResult<VehicleDto>.Validation("A valid license expiry date is required.");

            var fleetNumberTaken = await _context.Vehicles
                .AnyAsync(v => v.MunicipalityId == dto.MunicipalityId
                            && v.FleetNumber == dto.FleetNumber, cancellationToken);

            if (fleetNumberTaken)
                return ServiceResult<VehicleDto>.Conflict($"Fleet number '{dto.FleetNumber}' is already in use.");

            var registrationNumberTaken = await _context.Vehicles
                .AnyAsync(v => v.RegistrationNumber == dto.FleetNumber, cancellationToken);

            if (registrationNumberTaken)
                return ServiceResult<VehicleDto>.Conflict($"Registration number '{dto.RegistrationNumber}' is already in use.");

            var municipalityExists = await _context.Municipalities
                .AnyAsync(m => m.Id == dto.MunicipalityId, cancellationToken);

            if (!municipalityExists)
                return ServiceResult<VehicleDto>.Validation($"Municipality {dto.MunicipalityId} was not found.");

            if (dto.AssignedDriverId.HasValue)
            {
                var driverIsValid = await _context.Drivers
                    .AnyAsync(d => d.Id == dto.AssignedDriverId.Value
                                && d.MunicipalityId == dto.MunicipalityId, cancellationToken);

                if (!driverIsValid)
                    return ServiceResult<VehicleDto>.Validation(
                        "The assigned driver must belong to the name municipality as the vehicle.");
            }

            var vehicle = new Vehicle
            {
                Id = Guid.NewGuid(),
                FleetNumber = dto.FleetNumber,
                RegistrationNumber = dto.RegistrationNumber,
                Make = dto.Make,
                Model = dto.Model,
                LicenseExpiry = dto.LicenseExpiry.Value,
                Status = dto.Status,
                MunicipalityId = dto.MunicipalityId,
                AssignedDriverId = dto.AssignedDriverId
            };

            _context.Vehicles.Add(vehicle);

            try
            {
                await _context.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateException)
            {
                return ServiceResult<VehicleDto>.Conflict($"Fleet number '{dto.FleetNumber}' is already in use.");
            }

            return await GetByIdAsync(vehicle.Id, cancellationToken);
        }

        public async Task<ServiceResult<VehicleDto>> UpdateAsync(Guid id, UpdateVehicleDto dto, CancellationToken cancellationToken)
        {
            var vehicle = await _context.Vehicles
                .FirstOrDefaultAsync(v => v.Id == id, cancellationToken);

            if (vehicle is null)
                return ServiceResult<VehicleDto>.NotFound($"Vehicle {id} was not found.");

            if (dto.AssignedDriverId.HasValue)
            {
                var driverIsValid = await _context.Drivers
                    .AnyAsync(d => d.Id == dto.AssignedDriverId.Value
                                && d.MunicipalityId == vehicle.MunicipalityId, cancellationToken);

                if (!driverIsValid)
                    return ServiceResult<VehicleDto>.Validation(
                        "The assigned driver must belong to the same municipality as the vehicle.");
            }

            vehicle.RegistrationNumber = dto.RegistrationNumber;
            vehicle.Make = dto.Make;
            vehicle.Model = dto.Model;
            vehicle.LicenseExpiry = dto.LicenseExpiry;
            vehicle.Status = dto.Status;
            vehicle.AssignedDriverId = dto.AssignedDriverId;

            await _context.SaveChangesAsync(cancellationToken);

            return await GetByIdAsync(id, cancellationToken);
        }

        public async Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken)
        {
            var vehicle = await _context.Vehicles
                .FirstOrDefaultAsync(v => v.Id == id, cancellationToken);

            if (vehicle is null)
                return ServiceResult<bool>.NotFound($"Vehicle {id} was not found.");

            _context.Vehicles.Remove(vehicle);
            await _context.SaveChangesAsync(cancellationToken);

            return ServiceResult<bool>.Success(true);
        }

        private static VehicleDto MapToDto(Vehicle vehicle) => new()
        {
            Id = vehicle.Id,
            FleetNumber = vehicle.FleetNumber,
            RegistrationNumber = vehicle.RegistrationNumber,
            Make = vehicle.Make,
            Model = vehicle.Model,
            LicenseExpiry = vehicle.LicenseExpiry,
            Status = vehicle.Status,
            MunicipalityId = vehicle.MunicipalityId,
            MunicipalityName = vehicle.Municipality.Name,
            AssignedDriverId = vehicle.AssignedDriverId,
            AssignedDriverName = vehicle.AssignedDriver == null
                ? null
                : $"{vehicle.AssignedDriver.Name} {vehicle.AssignedDriver.Surname}",
            CreatedAt = vehicle.CreatedAt,
            UpdatedAt = vehicle.UpdatedAt
        };
    }
}
