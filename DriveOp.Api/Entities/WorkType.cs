using DriveOp.Api.Entities.Common;

namespace DriveOp.Api.Entities
{
    public class WorkType : BaseEntity
    {
        public string Name { get; set; } = null!;

        public Guid MunicipalityId { get; set; }
        public Municipality Municipality { get; set; } = null!;

        public Guid DepartmentId { get; set; }
        public Department Department { get; set; } = null!;

        public ICollection<Incident> Incidents { get; set; } = new List<Incident>();
    }
}
