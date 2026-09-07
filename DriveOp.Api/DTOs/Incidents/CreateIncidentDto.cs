using DriveOp.Api.Entities.Enums;
using System.ComponentModel.DataAnnotations;

namespace DriveOp.Api.DTOs.Incidents
{
    public class CreateIncidentDto
    {
        [Required, MaxLength(4000)]
        public string Description { get; set; } = null!;

        [Required]
        public IncidentType IncidentType { get; set; }

        [Required]
        public Guid VehicleId { get; set; }

        [Required]
        public Guid DriverId { get; set; }
    }
}
