using DriveOp.Api.Common;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.WorkTypes;

namespace DriveOp.Api.Services.WorkTypes
{
    public interface IWorkTypeService
    {
        Task<PagedResult<WorkTypeListDto>> GetAllAsync(WorkTypeQueryParameters parameters, CancellationToken cancellationToken);
        Task<ServiceResult<WorkTypeDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken);
        Task<ServiceResult<WorkTypeDto>> CreateAsync(CreateWorkTypeDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<bool>> UpdateAsync(Guid id, UpdateWorkTypeDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken);
    }
}
