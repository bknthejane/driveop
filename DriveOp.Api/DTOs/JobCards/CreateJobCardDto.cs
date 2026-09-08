using DriveOp.Api.Entities.Enums;
using System.ComponentModel.DataAnnotations;

namespace DriveOp.Api.DTOs.JobCards
{
    public class CreateJobCardDto
    {
        [Required]
        public Priority Priority { get; set; }

        [MaxLength(4000)]
        public string? Notes { get; set; }

        public Guid? AssignedSupervisorId { get; set; }
        public Guid? AssignedMechanicId { get; set; }
    }
}
