namespace DriveOp.Api.DTOs.Drivers
{
    public class DriverDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = null!;
        public string Surname { get; set; } = null!;
        public string LicenseNumber { get; set; } = null!;
        public Guid MunicipalityId { get; set; }
        public string MunicipalityName { get; set; } = null!;

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }
}
