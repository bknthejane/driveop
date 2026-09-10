namespace DriveOp.Api.DTOs.WorkTypes
{
    public class WorkTypeListDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = null!;
        public string DepartmentName { get; set; } = null!;
        public string? SupervisorName { get; set; }
    }
}
