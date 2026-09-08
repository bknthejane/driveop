using DriveOp.Api.Common;
using DriveOp.Api.DTOs.JobCards;
using DriveOp.Api.Services.JobCards;
using Microsoft.AspNetCore.Mvc;

namespace DriveOp.Api.Controllers
{
    [ApiController]
    [Route("api/jobcards")]
    public class JobCardsController : ControllerBase
    {
        private readonly IJobCardService _jobCardService;

        public JobCardsController(IJobCardService jobCardService)
        {
            _jobCardService = jobCardService;
        }

        [HttpGet("{id:guid}")]
        [ProducesResponseType(typeof(JobCardDto), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<IActionResult> GetById(Guid id, CancellationToken cancellationToken)
        {
            var result = await _jobCardService.GetByIdAsync(id, cancellationToken);
            return result.Succeeded ? Ok(result.Value) : ToErrorResponse(result);
        }

        [HttpPost("~/api/incidents/{incidentId:guid}/jobcards")]
        [ProducesResponseType(typeof(JobCardDto), StatusCodes.Status201Created)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        [ProducesResponseType(StatusCodes.Status409Conflict)]
        public async Task<IActionResult> CreateFromIncident(Guid incidentId, CreateJobCardDto dto, CancellationToken cancellationToken)
        {
            var result = await _jobCardService.CreateFromIncidentAsync(incidentId, dto, cancellationToken);

            if (!result.Succeeded)
                return ToErrorResponse(result);

            return CreatedAtAction(
                nameof(GetById),
                new { id = result.Value!.Id },
                result.Value);
        }

        [HttpPut("{id:guid}/status")]
        [ProducesResponseType(typeof(JobCardDto), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        [ProducesResponseType(StatusCodes.Status409Conflict)]
        public async Task<IActionResult> UpdateStatus(Guid id, UpdateJobCardStatusDto dto, CancellationToken cancellationToken)
        {
            var result = await _jobCardService.UpdateStatusAsync(id, dto, cancellationToken);
            return result.Succeeded ? Ok(result.Value) : ToErrorResponse(result);
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
