using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.DTOs.Drivers
{
    public class DriverListDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = null!;
        public string Surname { get; set; } = null!;
        public string LicenseNumber { get; set; } = null!;
    }
}
