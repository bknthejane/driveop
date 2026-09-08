using DriveOp.Api.Entities.Enums;
using System.ComponentModel.DataAnnotations;

namespace DriveOp.Api.DTOs.JobCards
{
    public class UpdateJobCardStatusDto
    {
        [Required]
        public JobCardStatus Status { get; set; }

        [MaxLength(4000)]
        public string? Notes { get; set; }
    }
}
