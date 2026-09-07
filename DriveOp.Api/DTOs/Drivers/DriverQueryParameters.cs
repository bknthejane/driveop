using DriveOp.Api.DTOs.Common;

namespace DriveOp.Api.DTOs.Drivers
{
    public class DriverQueryParameters : PagedRequest
    {
        public string? Search { get; set; }
        public Guid? MunicipalityId { get; set; }
    }
}
