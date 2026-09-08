using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.DTOs.JobCards
{
    public class JobCardDto
    {
        public Guid Id {  get; set; }
        public string JobCardNumber { get; set; } = null!;
        public JobCardStatus Status { get; set; }
        public Priority Priority { get; set; }
        public string? Notes { get; set; }
        public DateTime DateOpened { get; set; }
        public DateTime? DateCompleted { get; set; }

        public Guid IncidentId { get; set; }
        public string IncidentDescription { get; set; } = null!;
        public IncidentStatus IncidentStatus { get; set; }

        public Guid VehicleId { get; set; }
        public string VehicleFleetNumber { get; set; } = null!;
        public VehicleStatus VehicleStatus { get; set; }

        public Guid MunicipalityId { get; set; }
        public string MunicipalityName { get; set; } = null!;

        public Guid? AssignedSupervisorId { get; set; }
        public string? AssignedSupervisorName { get; set; }

        public Guid? AssignedMechanicId { get; set; }
        public string? AssignedMechanicName { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }
}
