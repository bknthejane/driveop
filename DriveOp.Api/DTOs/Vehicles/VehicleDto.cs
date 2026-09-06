using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.DTOs.Vehicles
{
    public class VehicleDto
    {
        public Guid Id { get; set; }
        public string FleetNumber { get; set; } = null!;
        public string RegistrationNumber { get; set; } = null!;
        public string Make { get; set; } = null!;
        public string Model { get; set; } = null!;
        public DateOnly LicenseExpiry { get; set; }
        public VehicleStatus Status { get; set; }

        public Guid MunicipalityId { get; set; }
        public string MunicipalityName { get; set; } = null!;

        public Guid? AssignedDriverId { get; set; }
        public string? AssignedDriverName { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }
}
