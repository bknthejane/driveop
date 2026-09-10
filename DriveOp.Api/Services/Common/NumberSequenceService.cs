using DriveOp.Api.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace DriveOp.Api.Services.Common
{
    public class NumberSequenceService : INumberSequenceService
    {
        private const int UniqueConstraintViolation = 2627;
        private const int UniqueIndexViolation = 2601;

        private readonly DriveOpDbContext _context;

        public NumberSequenceService(DriveOpDbContext context)
        {
            _context = context;
        }

        public async Task<int> NextAsync(Guid municipalityId, string sequenceName, string periodKey, CancellationToken cancellationToken)
        {
            var next = await TryIncrementAsync(municipalityId, sequenceName, periodKey, cancellationToken);

            if (next.HasValue)
                return next.Value;

            // The counter row does not exist yet - first allocation for this
            // period. Create it, tolerating a concurrent creator.
            try
            {
                await _context.Database.ExecuteSqlRawAsync(
                    """
                    INSERT INTO NumberSequences (MunicipalityId, SequenceName, PeriodKey, LastValue)
                    VALUES (@municipalityId, @sequenceName, @periodKey, 0)
                    """,
                    new[]
                    {
                        new SqlParameter("@municipalityId", municipalityId),
                        new SqlParameter("@sequenceName", sequenceName),
                        new SqlParameter("@periodKey", periodKey)
                    },
                    cancellationToken);  
            }
            catch (DbUpdateException ex) when (IsDuplicateKey(ex))
            {
                //Another request created the row first. Fine - increment it.
            }
            catch (SqlException ex) when (IsDuplicateKey(ex))
            {
                //Same, when the provider surfaces SqlException directly.
            }

            next = await TryIncrementAsync(municipalityId, sequenceName, periodKey, cancellationToken);

            if (next.HasValue)
                return next.Value;

            throw new InvalidOperationException(
                $"Could not allocate a number for sequence '{sequenceName}' " +
                $"in municipality {municipalityId}.");
        }

        private async Task<int?> TryIncrementAsync(Guid municipalityId, string sequenceName, string periodKey, CancellationToken cancellationToken)
        {
            var connection = _context.Database.GetDbConnection();
            var transaction = _context.Database.CurrentTransaction;

            await using var command = connection.CreateCommand();

            command.CommandText =
                """
                UPDATE NumberSequences
                SET LastValue = LastValue + 1
                OUTPUT INSERTED.LastValue
                WHERE MunicipalityId = @municipalityId
                    AND SequenceName = @sequenceName
                    AND PeriodKey = @periodKey
                """;

            command.Parameters.Add(new SqlParameter("@municipalityId", municipalityId));
            command.Parameters.Add(new SqlParameter("@sequenceName", sequenceName));
            command.Parameters.Add(new SqlParameter("@periodKey", periodKey));

            if (transaction is not null)
                command.Transaction = transaction.GetDbTransaction();

            if (connection.State != System.Data.ConnectionState.Open)
                await connection.OpenAsync(cancellationToken);

            var result = await command.ExecuteScalarAsync(cancellationToken);

            return result is null or DBNull ? null : Convert.ToInt32(result);
        }

        private static bool IsDuplicateKey(DbUpdateException exception) =>
            exception.InnerException is SqlException sql && IsDuplicateKey(sql);

        private static bool IsDuplicateKey(SqlException exception) =>
            exception.Number is UniqueConstraintViolation or UniqueIndexViolation;
    }
}
