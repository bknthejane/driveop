using DriveOp.Api.Entities.Common;
using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.Entities
{
    public class Incident : BaseEntity
    {
        public string Description { get; set; } = null!;
        public IncidentStatus Status { get; set; } = IncidentStatus.Reported;
        public DateTime DateReported { get; set; }

        public Guid WorkTypeId { get; set; }
        public WorkType WorkType { get; set; } = null!;

        public Guid DepartmentId { get; set; }
        public Department Department { get; set; } = null!;

        public Guid VehicleId { get; set; }
        public Vehicle Vehicle { get; set; } = null!;

        public Guid DriverId { get; set; }
        public Driver Driver { get; set; } = null!;

        public JobCard? JobCard { get; set; }
    }
}
