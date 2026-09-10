using System.ComponentModel.DataAnnotations;

namespace DriveOp.Api.DTOs.WorkTypes
{
    public class UpdateWorkTypeDto
    {
        [Required, MaxLength(100)]
        public string Name { get; set; } = null!;

        [Required]
        public Guid DepartmentId { get; set; }
    }
}
