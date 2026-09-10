namespace DriveOp.Api.DTOs.WorkTypes
{
    public class WorkTypeDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = null!;

        public Guid DepartmentId { get; set; }
        public string DepartmentName { get; set; } = null!;

        public Guid MunicipalityId { get; set; }
        public string MunicipalityName { get; set; } = null!;

        public Guid? SupervisorId { get; set; }
        public string? SupervisorName { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }
}
