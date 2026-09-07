using System.ComponentModel.DataAnnotations;

namespace DriveOp.Api.DTOs.Drivers
{
    public class UpdateDriverDto
    {
        [Required, MaxLength(100)]
        public string Name { get; set; } = null!;

        [Required, MaxLength(100)]
        public string Surname { get; set; } = null!;

        [Required, MaxLength(50)]
        public string LicenseNumber { get; set; } = null!;
    }
}
