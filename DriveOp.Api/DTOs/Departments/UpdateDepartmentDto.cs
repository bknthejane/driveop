using System.ComponentModel.DataAnnotations;

namespace DriveOp.Api.DTOs.Departments
{
    public class UpdateDepartmentDto
    {
        [Required, MaxLength(100)]
        public string Name { get; set; } = null!;

        [MaxLength(500)]
        public string? Description { get; set; }
    }
}
