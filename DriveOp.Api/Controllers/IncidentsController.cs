using DriveOp.Api.Common;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Incidents;
using DriveOp.Api.Services.Incidents;
using Microsoft.AspNetCore.Mvc;

namespace DriveOp.Api.Controllers
{
    [ApiController]
    [Route("api/incidents")]
    public class IncidentsController : ControllerBase
    {
        private readonly IIncidentService _incidentService;

        public IncidentsController(IIncidentService incidentService)
        {
            _incidentService = incidentService;
        }

        [HttpGet]
        [ProducesResponseType(typeof(PagedResult<IncidentListDto>), StatusCodes.Status200OK)]
        public async Task<IActionResult> GetAll([FromQuery] IncidentQueryParameters parameters, CancellationToken cancellationToken)
        {
            var incidents = await _incidentService.GetAllAsync(parameters, cancellationToken);
            return Ok(incidents);
        }

        [HttpGet("{id:guid}")]
        [ProducesResponseType(typeof(IncidentDto), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<IActionResult> GetById(Guid id, CancellationToken cancellationToken)
        {
            var result = await _incidentService.GetByIdAsync(id, cancellationToken);
            return result.Succeeded ? Ok(result.Value) : ToErrorResponse(result);
        }

        [HttpPost]
        [ProducesResponseType(typeof(IncidentDto), StatusCodes.Status201Created)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status409Conflict)]
        public async Task<IActionResult> Create(CreateIncidentDto dto, CancellationToken cancellationToken)
        {
            var result = await _incidentService.CreateAsync(dto, cancellationToken);

            if (!result.Succeeded)
                return ToErrorResponse(result);

            return CreatedAtAction(
                nameof(GetById),
                new { id = result.Value!.Id },
                result.Value);
        }

        [HttpDelete("{id:guid}")]
        [ProducesResponseType(StatusCodes.Status204NoContent)]
        [ProducesResponseType(StatusCodes.Status409Conflict)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken)
        {
            var result = await _incidentService.DeleteAsync(id, cancellationToken);
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
