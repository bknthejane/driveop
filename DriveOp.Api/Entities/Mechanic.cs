using DriveOp.Api.Entities.Common;

namespace DriveOp.Api.Entities
{
    public class Mechanic : BaseEntity
    {
        public string Name { get; set; } = null!;
        public string Surname { get; set; } = null!;

        public Guid MunicipalityId { get; set; }
        public Municipality Municipality { get; set; } = null!;

        public Guid? SupervisorId { get; set; }
        public Supervisor? Supervisor { get; set; }

        public ICollection<JobCard> JobCards { get; set; } = new List<JobCard>();
    }
}
