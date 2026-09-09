using DriveOp.Api.DTOs.Common;
using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.DTOs.JobCards
{
    public class JobCardQueryParameters : PagedRequest
    {
        public JobCardStatus? Status { get; set; }
        public Priority? Priority { get; set; }
        public Guid? MunicipalityId { get; set; }
        public Guid? AssignedSupervisorId { get; set; }
        public Guid? AssignedMechanicId { get; set; }
        public bool? Unassigned { get; set; }
    }
}
