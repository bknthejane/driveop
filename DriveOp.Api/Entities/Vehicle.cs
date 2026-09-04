using DriveOp.Api.Entities.Common;
using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.Entities
{
    public class Vehicle : BaseEntity
    {
        public string FleetNumber { get; set; } = null!;
        public string RegistrationNumber { get; set; } = null!;
        public string Make { get; set; } = null!;
        public string Model { get; set; } = null!;
        public DateOnly LicenseExpiry { get; set; }
        public VehicleStatus Status { get; set; }

        public Guid MunicipalityId { get; set; }
        public Municipality Municipality { get; set; } = null!;

        public Guid? AssignedDriverId { get; set; }
        public Driver? AssignedDriver { get; set; }

        public ICollection<Incident> Incidents { get; set; } = new List<Incident>();
    }
}
