using DriveOp.Api.Common;
using DriveOp.Api.DTOs.Vehicles;

namespace DriveOp.Api.Services
{
    public interface IVehicleService
    {
        Task<IReadOnlyList<VehicleListDto>> GetAllAsync(CancellationToken cancellationToken);
        Task<ServiceResult<VehicleDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken);
        Task<ServiceResult<VehicleDto>> CreateAsync(CreateVehicleDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<VehicleDto>> UpdateAsync(Guid id, UpdateVehicleDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken);
    }
}
