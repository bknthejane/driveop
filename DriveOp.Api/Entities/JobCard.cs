using DriveOp.Api.Entities.Common;
using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.Entities
{
    public class JobCard : BaseEntity
    {
        public string JobCardNumber { get; set; } = null!;
        public JobCardStatus Status { get; set; } = JobCardStatus.Open;
        public Priority Priority { get; set; } = Priority.Low;
        public string? Notes { get; set; }
        public DateTime DateOpened { get; set; }
        public DateTime? DateCompleted { get; set; }

        public Guid MunicipalityId { get; set; }
        public Municipality Municipality { get; set; } = null!;

        public Guid IncidentId { get; set; }
        public Incident Incident { get; set; } = null!;

        public Guid? AssignedSupervisorId { get; set; }
        public Supervisor? AssignedSupervisor { get; set; }

        public Guid? AssignedMechanicId { get; set; }
        public Mechanic? AssignedMechanic { get; set; }
    }
}
