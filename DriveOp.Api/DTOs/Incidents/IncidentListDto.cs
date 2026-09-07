using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.DTOs.Incidents
{
    public class IncidentListDto
    {
        public Guid Id { get; set; }
        public IncidentType IncidentType { get; set; }
        public IncidentStatus Status { get; set; }
        public DateTime DateReported { get; set; }
        public string VehicleFleetNumber { get; set; } = null!;
        public string DriverName { get; set; } = null!;
        public bool HasJobCard { get; set; }
    }
}
