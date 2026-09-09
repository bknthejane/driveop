using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.DTOs.JobCards
{
    public class JobCardListDto
    {
        public Guid Id { get; set; }
        public string JobCardNumber { get; set; } = null!;
        public JobCardStatus Status { get; set; }
        public Priority Priority { get; set; }
        public DateTime DateOpened { get; set; }
        public DateTime? DateCompleted { get; set; }

        public string VehicleFleetNumber { get; set; } = null!;
        public IncidentType IncidentType { get; set; }

        public string? AssignedSupervisorName { get; set; }
        public string? AssignedMechanicName { get; set; }
    }
}
