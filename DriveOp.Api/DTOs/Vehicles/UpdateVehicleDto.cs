using DriveOp.Api.Entities.Enums;
using System.ComponentModel.DataAnnotations;

namespace DriveOp.Api.DTOs.Vehicles
{
    public class UpdateVehicleDto
    {
        [Required, MaxLength(20)]
        public string RegistrationNumber { get; set; } = null!;

        [Required, MaxLength(100)]
        public string Make { get; set; } = null!;

        [Required, MaxLength(100)]
        public string Model { get; set; } = null!;

        [Required]
        public DateOnly LicenseExpiry { get; set; }

        [Required]
        public VehicleStatus Status { get; set; }

        public Guid? AssignedDriverId { get; set; }
    }
}
