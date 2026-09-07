using DriveOp.Api.Common;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Vehicles;

namespace DriveOp.Api.Services.Vehicles
{
    public interface IVehicleService
    {
        Task<PagedResult<VehicleListDto>> GetAllAsync(VehicleQueryParameters parameters, CancellationToken cancellationToken);
        Task<ServiceResult<VehicleDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken);
        Task<ServiceResult<VehicleDto>> CreateAsync(CreateVehicleDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<VehicleDto>> UpdateAsync(Guid id, UpdateVehicleDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken);
    }
}
