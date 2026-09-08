using DriveOp.Api.Entities.Enums;

namespace DriveOp.Api.Common
{
    public class JobCardStatusTransactions
    {
        private static readonly Dictionary<JobCardStatus, JobCardStatus[]> Allowed = new()
        {
            [JobCardStatus.Open] = new[]
            {
                JobCardStatus.InProgress,
                JobCardStatus.Cancelled
            },
            [JobCardStatus.InProgress] = new[]
            {
                JobCardStatus.Completed,
                JobCardStatus.Cancelled
            },
            [JobCardStatus.Completed] = Array.Empty<JobCardStatus>(),
            [JobCardStatus.Cancelled] = Array.Empty<JobCardStatus>()
        };

        public static bool IsAllowed(JobCardStatus from, JobCardStatus to) =>
            Allowed.TryGetValue(from, out var targets) && targets.Contains(to);

        public static IReadOnlyList<JobCardStatus> AllowedFrom(JobCardStatus from) =>
            Allowed.TryGetValue(from, out var targets) ? targets : Array.Empty<JobCardStatus>();
    }
}
