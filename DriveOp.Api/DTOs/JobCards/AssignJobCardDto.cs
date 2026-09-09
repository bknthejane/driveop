using DriveOp.Api.Entities;

namespace DriveOp.Api.DTOs.JobCards
{
    public class AssignJobCardDto
    {
        public Guid? AssignedSupervisorId { get; set; }
        public Guid? AssignedMechanicId { get; set; }
    }
}
