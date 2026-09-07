using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace DriveOp.Api.Common
{
    public class GlobalExceptionHandler : IExceptionHandler
    {
        private const int UniqueIndexViolation = 2601;
        private const int UniqueConstraintViolation = 2627;

        private readonly ILogger<GlobalExceptionHandler> _logger;
        private readonly IHostEnvironment _environment;

        public GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger, IHostEnvironment environment)
        {
            _logger = logger;
            _environment = environment;
        }

        public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
        {
            var traceId = httpContext.TraceIdentifier;

            _logger.LogError(
                exception,
                "Unhandled exception on {Method} {Path}. TraceId: {TraceId}",
                httpContext.Request.Method,
                httpContext.Request.Path,
                traceId);

            var problem = BuildProblemDetails(exception, traceId);

            httpContext.Response.StatusCode = problem.Status ?? StatusCodes.Status500InternalServerError;
            await httpContext.Response.WriteAsJsonAsync(problem, cancellationToken);

            return true;
        }

        private ProblemDetails BuildProblemDetails(Exception exception, string traceId)
        {
            var problem = exception switch
            {
                DbUpdateException dbEx when IsUniqueViolation(dbEx) => new ProblemDetails
                {
                    Title = "Conflict",
                    Detail = "A record with the same unique value already exists.",
                    Status = StatusCodes.Status409Conflict
                },
                DbUpdateConcurrencyException => new ProblemDetails
                {
                    Title = "Concurrency conflict",
                    Detail = "This record was modified by someone else. Reload and try again.",
                    Status = StatusCodes.Status409Conflict
                },
                OperationCanceledException => new ProblemDetails
                {
                    Title = "Request cancelled",
                    Detail = "The request was cancelled before it completed.",
                    Status = StatusCodes.Status499ClientClosedRequest
                },
                _ => new ProblemDetails
                {
                    Title = "An unexpected error occurred",
                    Detail = "An unexpected error occurred while processing your request.",
                    Status = StatusCodes.Status500InternalServerError
                }
            };

            problem.Extensions["traceId"] = traceId;

            if (_environment.IsDevelopment())
            {
                problem.Extensions["exception"] = exception.GetType().Name;
                problem.Extensions["exceptionMessage"] = exception.Message;
                problem.Extensions["stackTrace"] = exception.StackTrace;
            }

            return problem;
        }

        private static bool IsUniqueViolation(DbUpdateException exception) =>
            exception.InnerException is SqlException sql &&
            (sql.Number == UniqueIndexViolation || sql.Number == UniqueConstraintViolation);
    }
}
