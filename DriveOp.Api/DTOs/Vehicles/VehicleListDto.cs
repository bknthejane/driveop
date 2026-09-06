using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.DTOs.Vehicles
{
    public class VehicleListDto
    {
        public Guid Id { get; set; }
        public string FleetNumber { get; set; } = null!;
        public string RegistrationNumber { get; set; } = null!;
        public string Make { get; set; } = null!;
        public string Model { get; set; } = null!;
        public DateOnly LicenseExpiry {  get; set; }
        public VehicleStatus Status { get; set; }
        public string? AssignedDriverName { get; set; }
    }
}
