using DriveOp.Api.Entities.Common;

namespace DriveOp.Api.Entities
{
    public class Driver : BaseEntity
    {
        public string Name { get; set; } = null!;
        public string Surname { get; set; } = null!;
        public string LicenseNumber { get; set; } = null!;

        public Guid MunicipalityId { get; set; }
        public Municipality Municipality { get; set; } = null!;

        public ICollection<Vehicle> AssignedVehicles { get; set; } = new List<Vehicle>();
        public ICollection<Incident> Incidents { get; set; } = new List<Incident>();
    }
}
