using DriveOp.Api.Common;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Incidents;

namespace DriveOp.Api.Services.Incidents
{
    public interface IIncidentService
    {
        Task<PagedResult<IncidentListDto>> GetAllAsync(IncidentQueryParameters parameters, CancellationToken cancellationToken);
        Task<ServiceResult<IncidentDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken);
        Task<ServiceResult<IncidentDto>> CreateAsync(CreateIncidentDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<bool>> DeleteAsync(Guid id, CancellationToken cancellationToken);
    }
}
