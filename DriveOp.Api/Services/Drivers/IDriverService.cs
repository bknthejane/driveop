using DriveOp.Api.Common;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Drivers;

namespace DriveOp.Api.Services.Drivers
{
    public interface IDriverService
    {
        Task<PagedResult<DriverListDto>> GetAllAsync(DriverQueryParameters parameters, CancellationToken cancellationToken);
        Task<ServiceResult<DriverDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken);
        Task<ServiceResult<DriverDto>> CreateAsync(CreateDriverDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<DriverDto>> UpdateAsync(Guid id, UpdateDriverDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken);
    }
}
