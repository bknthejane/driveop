using DriveOp.Api.Common;
using DriveOp.Api.DTOs.Common;
using DriveOp.Api.DTOs.Drivers;
using DriveOp.Api.Services.Drivers;
using Microsoft.AspNetCore.Mvc;

namespace DriveOp.Api.Controllers
{
    [ApiController]
    [Route("api/drivers")]
    public class DriversController : ControllerBase
    {
        private readonly IDriverService _driverService;

        public DriversController(IDriverService driverService)
        {
            _driverService = driverService;
        }

        [HttpGet]
        [ProducesResponseType(typeof(PagedResult<DriverListDto>), StatusCodes.Status200OK)]
        public async Task<IActionResult> GetAll([FromQuery] DriverQueryParameters parameters, CancellationToken cancellationToken)
        {
            var drivers = await _driverService.GetAllAsync(parameters, cancellationToken);
            return Ok(drivers);
        }

        [HttpGet("{id:guid}")]
        [ProducesResponseType(typeof(DriverDto), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<IActionResult> GetById(Guid id, CancellationToken cancellationToken)
        {
            var result = await _driverService.GetByIdAsync(id, cancellationToken);
            return result.Succeeded ? Ok(result.Value) : ToErrorResponse(result);
        }

        [HttpPost]
        [ProducesResponseType(typeof(DriverDto), StatusCodes.Status201Created)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status409Conflict)]
        public async Task<IActionResult> Create(CreateDriverDto dto, CancellationToken cancellationToken)
        {
            var result = await _driverService.CreateAsync(dto, cancellationToken);

            if (!result.Succeeded)
                return ToErrorResponse(result);

            return CreatedAtAction(
                nameof(GetById),
                new { id = result.Value!.Id },
                result.Value);
        }

        [HttpPut("{id:guid}")]
        [ProducesResponseType(StatusCodes.Status204NoContent)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<IActionResult> Update(Guid id, UpdateDriverDto dto, CancellationToken cancellationToken)
        {
            var result = await _driverService.UpdateAsync(id, dto, cancellationToken);
            return result.Succeeded ? NoContent() : ToErrorResponse(result);
        }

        [HttpDelete("{id:guid}")]
        [ProducesResponseType(StatusCodes.Status204NoContent)]
        [ProducesResponseType(StatusCodes.Status409Conflict)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken)
        {
            var result = await _driverService.DeleteAsync(id, cancellationToken);
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
