namespace DriveOp.Api.Common
{
    public enum ServiceErrorType
    {
        None = 0,
        NotFound = 1,
        Conflict = 2,
        Validation = 3
    }
    public class ServiceResult<T>
    {
        public bool Succeeded { get; private init; }
        public T? Value { get; private init; }
        public ServiceErrorType ErrorType { get; private init; }
        public string? ErrorMessage { get; private init; }

        public static ServiceResult<T> Success(T value) =>
            new() { Succeeded = true, Value = value };

        public static ServiceResult<T> NotFound(string message) =>
            new() { Succeeded = false, ErrorType = ServiceErrorType.NotFound, ErrorMessage = message };

        public static ServiceResult<T> Conflict(string message) =>
            new() { Succeeded = false, ErrorType = ServiceErrorType.Conflict, ErrorMessage = message };

        public static ServiceResult<T> Validation(string message) =>
            new() { Succeeded = false, ErrorType = ServiceErrorType.Validation, ErrorMessage = message };
    }
}
