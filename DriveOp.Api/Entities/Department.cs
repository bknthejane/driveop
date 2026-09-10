using DriveOp.Api.Entities.Common;

namespace DriveOp.Api.Entities
{
    public class Department : BaseEntity
    {
        public string Name { get; set; } = null!;
        public string? Description { get; set; }

        public Guid MunicipalityId { get; set; }
        public Municipality Municipality { get; set; } = null!;

        public Supervisor? Supervisor { get; set; }

        public ICollection<WorkType> WorkTypes { get; set; } = new List<WorkType>();
        public ICollection<Mechanic> Mechanics { get; set; } = new List<Mechanic>();
    }
}
