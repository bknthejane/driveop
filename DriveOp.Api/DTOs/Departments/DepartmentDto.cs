namespace DriveOp.Api.DTOs.Departments
{
    public class DepartmentDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = null!;
        public string? Description { get; set; }

        public Guid MunicipalityId { get; set; }
        public string MunicipalityName { get; set; } = null!;

        public Guid? SupervisorId { get; set; }
        public string? SupervisorName { get; set; }

        public int WorkTypeCount { get; set; }
        public int MechanicCount { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }
}
