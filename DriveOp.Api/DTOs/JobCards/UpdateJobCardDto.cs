using DriveOp.Api.Entities.Enums;
using System.ComponentModel.DataAnnotations;

namespace DriveOp.Api.DTOs.JobCards
{
    public class UpdateJobCardDto
    {
        [Required]
        public Priority Priority { get; set; }

        [MaxLength(4000)]
        public string? Notes { get; set; }
    }
}
