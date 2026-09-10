using DriveOp.Api.Common;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Departments;
using DriveOp.Api.Services.Departments;
using Microsoft.AspNetCore.Mvc;

namespace DriveOp.Api.Controllers
{
    [ApiController]
    [Route("api/departments")]
    public class DepartmentsController : ControllerBase
    {
        private readonly IDepartmentService _departmentService;

        public DepartmentsController(IDepartmentService departmentService)
        {
            _departmentService = departmentService;
        }

        [HttpGet]
        [ProducesResponseType(typeof(PagedResult<DepartmentListDto>), StatusCodes.Status200OK)]
        public async Task<IActionResult> GetAll(
            [FromQuery] DepartmentQueryParameters parameters,
            CancellationToken cancellationToken)
        {
            var result = await _departmentService.GetAllAsync(parameters, cancellationToken);
            return Ok(result);
        }

        [HttpGet("{id:guid}")]
        [ProducesResponseType(typeof(DepartmentDto), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<IActionResult> GetById(Guid id, CancellationToken cancellationToken)
        {
            var result = await _departmentService.GetByIdAsync(id, cancellationToken);
            return result.Succeeded ? Ok(result.Value) : ToErrorResponse(result);
        }

        [HttpPost]
        [ProducesResponseType(typeof(DepartmentDto), StatusCodes.Status201Created)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status409Conflict)]
        public async Task<IActionResult> Create(
            CreateDepartmentDto dto, CancellationToken cancellationToken)
        {
            var result = await _departmentService.CreateAsync(dto, cancellationToken);

            if (!result.Succeeded)
                return ToErrorResponse(result);

            return CreatedAtAction(nameof(GetById), new { id = result.Value!.Id }, result.Value);
        }

        [HttpPut("{id:guid}")]
        [ProducesResponseType(StatusCodes.Status204NoContent)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        [ProducesResponseType(StatusCodes.Status409Conflict)]
        public async Task<IActionResult> Update(
            Guid id, UpdateDepartmentDto dto, CancellationToken cancellationToken)
        {
            var result = await _departmentService.UpdateAsync(id, dto, cancellationToken);
            return result.Succeeded ? NoContent() : ToErrorResponse(result);
        }

        [HttpDelete("{id:guid}")]
        [ProducesResponseType(StatusCodes.Status204NoContent)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        [ProducesResponseType(StatusCodes.Status409Conflict)]
        public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken)
        {
            var result = await _departmentService.DeleteAsync(id, cancellationToken);
            return result.Succeeded ? NoContent() : ToErrorResponse(result);
        }

        private IActionResult ToErrorResponse<T>(ServiceResult<T> result) =>
            result.ErrorType switch
            {
                ServiceErrorType.NotFound => NotFound(new ProblemDetails
                {
                    Title = "Not found",
                    Detail = result.ErrorMessage,
                    Status = StatusCodes.Status404NotFound
                }),
                ServiceErrorType.Conflict => Conflict(new ProblemDetails
                {
                    Title = "Conflict",
                    Detail = result.ErrorMessage,
                    Status = StatusCodes.Status409Conflict
                }),
                _ => BadRequest(new ProblemDetails
                {
                    Title = "Validation failed",
                    Detail = result.ErrorMessage,
                    Status = StatusCodes.Status400BadRequest
                })
            };
    }
}
