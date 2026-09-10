using DriveOp.Api.Common;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Departments;

namespace DriveOp.Api.Services.Departments
{
    public interface IDepartmentService
    {
        Task<PagedResult<DepartmentListDto>> GetAllAsync(DepartmentQueryParameters parameters, CancellationToken cancellationToken);
        Task<ServiceResult<DepartmentDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken);
        Task<ServiceResult<DepartmentDto>> CreateAsync(CreateDepartmentDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<bool>> UpdateAsync(Guid id, UpdateDepartmentDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken);
    }
}
