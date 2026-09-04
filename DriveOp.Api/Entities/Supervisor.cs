using DriveOp.Api.Entities.Common;

namespace DriveOp.Api.Entities
{
    public class Supervisor : BaseEntity
    {
        public string Name { get; set; } = null!;
        public string Surname { get; set; } = null!;
        public string Email { get; set; } = null!;

        public Guid MunicipalityId { get; set; }
        public Municipality Municipality { get; set; } = null!;

        public ICollection<Mechanic> Mechanics { get; set; } = new List<Mechanic>();
        public ICollection<JobCard> JobCards { get; set; } = new List<JobCard>();
    }
}
