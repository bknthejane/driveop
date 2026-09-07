using DriveOp.Api.DTOs.Common;
using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.DTOs.Incidents
{
    public class IncidentQueryParameters : PagedRequest
    {
        public Guid? VehicleId { get; set; }
        public Guid? DriverId { get; set; }
        public Guid? MunicipalityId { get; set; }
        public IncidentStatus? Status { get; set; }
        public IncidentType? IncidentType { get; set; }
    }
}
