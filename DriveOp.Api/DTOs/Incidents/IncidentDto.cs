using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.DTOs.Incidents
{
    public class IncidentDto
    {
        public Guid Id { get; set; }
        public string Description { get; set; } = null!;
        public Guid WorkTypeId { get; set; }
        public string WorkTypeName { get; set; } = null!;

        public Guid DepartmentId { get; set; }
        public string DepartmentName { get; set; } = null!;
        public IncidentStatus Status { get; set; }
        public DateTime DateReported { get; set; }

        public Guid VehicleId { get; set; }
        public string VehicleFleetNumber { get; set; } = null!;
        public string VehicleRegistrationNumber { get; set; } = null!;

        public Guid DriverId { get; set; }
        public string DriverName { get; set; } = null!;

        public Guid MunicipalityId { get; set; }
        public string MunicipalityName { get; set;} = null!;

        public bool HasJobCard { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }
}
