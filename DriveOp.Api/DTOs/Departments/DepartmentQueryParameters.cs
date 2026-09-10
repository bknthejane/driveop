using DriveOp.Api.DTOs.Common;

namespace DriveOp.Api.DTOs.Departments
{
    public class DepartmentQueryParameters : PagedRequest
    {
        public Guid? MunicipalityId { get; set; }
        public string? Search {  get; set; }
        public bool? Unstaffed { get; set; }
    }
}
