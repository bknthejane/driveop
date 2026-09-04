using DriveOp.Api.Entities.Common;

namespace DriveOp.Api.Entities
{
    public class Municipality : BaseEntity
    {
        public string Name { get; set; } = null!;
        public string Code { get; set; } = null!;
        public string? Province { get; set; }

        public ICollection<Vehicle> Vehicles { get; set; } = new List<Vehicle>();
        public ICollection<Driver> Drivers { get; set; } = new List<Driver>();
        public ICollection<Supervisor> Supervisors { get; set; } = new List<Supervisor>();
        public ICollection<Mechanic> Mechanics { get; set; } = new List<Mechanic>();
    }
}
