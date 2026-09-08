using DriveOp.Api.Common;
using DriveOp.Api.DTOs.JobCards;

namespace DriveOp.Api.Services.JobCards
{
    public interface IJobCardService
    {
        Task<ServiceResult<JobCardDto>> GetByIdAsync(Guid id, CancellationToken cancellationToken);
        Task<ServiceResult<JobCardDto>> CreateFromIncidentAsync(Guid incidentId, CreateJobCardDto dto, CancellationToken cancellationToken);
        Task<ServiceResult<JobCardDto>> UpdateStatusAsync(Guid id, UpdateJobCardStatusDto dto, CancellationToken cancellationToken);
    }
}
