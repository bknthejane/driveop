using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DriveOp.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddNumberSequences : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "NumberSequences",
                columns: table => new
                {
                    MunicipalityId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    SequenceName = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    PeriodKey = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    LastValue = table.Column<int>(type: "int", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NumberSequences", x => new { x.MunicipalityId, x.SequenceName, x.PeriodKey });
                    table.ForeignKey(
                        name: "FK_NumberSequences_Municipalities_MunicipalityId",
                        column: x => x.MunicipalityId,
                        principalTable: "Municipalities",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "NumberSequences");
        }
    }
}
