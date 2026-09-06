using DriveOp.Api.DTOs.Common;
using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.DTOs.Vehicles
{
    public class VehicleQueryParameters : PagedRequest
    {
        public string? Search {  get; set; }
        public VehicleStatus? Status { get; set; }
        public Guid? MunicipalityId { get; set; }
    }
}
