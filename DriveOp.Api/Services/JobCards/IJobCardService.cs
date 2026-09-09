using DriveOp.Api.Common;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.JobCards;

namespace DriveOp.Api.Services.JobCards
{
    public interface IJobCardService
    {
        Task<PagedResult<JobCardListDto>> GetAllAsync(JobCardQueryParameters parameters, CancellationToken cancellationToken);
        Task<ServiceResult<JobCardDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken);
        Task<ServiceResult<JobCardDto>> CreateFromIncidentAsync(Guid incidentId, CreateJobCardDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<JobCardDto>> UpdateStatusAsync(Guid id, UpdateJobCardStatusDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<bool>> UpdateAsync(Guid id, UpdateJobCardDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<JobCardDto>> AssignAsync(Guid id, AssignJobCardDto dto, CancellationToken cancellationToken);
    }
}
