namespace DriveOp.Api.Services.Common
{
    public interface INumberSequenceService
    {
        Task<int> NextAsync(Guid municipalityId, string sequenceName, string periodKey, CancellationToken cancellationToken);
    }
}
