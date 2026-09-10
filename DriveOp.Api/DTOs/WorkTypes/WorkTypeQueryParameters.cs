using DriveOp.Api.DTOs.Common;

namespace DriveOp.Api.DTOs.WorkTypes
{
    public class WorkTypeQueryParameters : PagedRequest
    {
        public Guid? MunicipalityId { get; set; }
        public Guid? DepartmentId { get; set; }
        public string? Search {  get; set; }
    }
}
