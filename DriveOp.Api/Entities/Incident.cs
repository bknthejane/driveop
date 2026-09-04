using DriveOp.Api.Entities.Common;
using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.Entities
{
    public class Incident : BaseEntity
    {
        public string Description { get; set; } = null!;
        public IncidentType IncidentType { get; set; }
        public IncidentStatus Status { get; set; } = IncidentStatus.Reported;
        public DateTime DateReported { get; set; }

        public Guid VehicleId { get; set; }
        public Vehicle Vehicle { get; set; } = null!;

        public Guid DriverId { get; set; }
        public Driver Driver { get; set; } = null!;

        public JobCard? JobCard { get; set; }
    }
}
