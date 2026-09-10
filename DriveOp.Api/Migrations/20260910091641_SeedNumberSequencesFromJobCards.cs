using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DriveOp.Api.Migrations
{
    /// <inheritdoc />
    public partial class SeedNumberSequencesFromJobCards : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                INSERT INTO NumberSequences (MunicipalityId, SequenceName, PeriodKey, LastValue)
                SELECT
                    j.MunicipalityId,
                    'JobCard',
                    SUBSTRING(j.JobCardNumber, 4, 8),
                    MAX(CAST(SUBSTRING(j.JobCardNumber, 13, LEN(j.JobCardNumber) - 12) AS int))
                FROM JobCards j
                WHERE j.JobCardNumber LIKE 'JC-________-%'
                AND ISNUMERIC(SUBSTRING(j.JobCardNumber, 13, LEN(j.JobCardNumber) - 12)) = 1
                AND NOT EXISTS (
                    SELECT 1 FROM NumberSequences n
                    WHERE n.MunicipalityId = j.MunicipalityId
                        AND n.SequenceName = 'JobCard'
                        AND n.PeriodKey = SUBSTRING(j.JobCardNumber, 4, 8)
                )
                GROUP BY j.MunicipalityId, SUBSTRING(j.JobCardNumber, 4, 8);
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("DELETE FROM NumberSequences WHERE SequenceName = 'JobCard';");
        }
    }
}
