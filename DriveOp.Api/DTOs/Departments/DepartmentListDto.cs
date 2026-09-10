namespace DriveOp.Api.DTOs.Departments
{
    public class DepartmentListDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = null!;
        public string? SupervisorName { get; set; }
        public int WorkTypeCount { get; set; }
        public int MechanicCount { get; set; }
    }
}
