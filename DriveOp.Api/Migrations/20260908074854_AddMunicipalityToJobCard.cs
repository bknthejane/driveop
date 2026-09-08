using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DriveOp.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddMunicipalityToJobCard : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_JobCards_JobCardNumber",
                table: "JobCards");

            migrationBuilder.AddColumn<Guid>(
                name: "MunicipalityId",
                table: "JobCards",
                type: "uniqueidentifier",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));

            migrationBuilder.CreateIndex(
                name: "IX_JobCards_MunicipalityId_JobCardNumber",
                table: "JobCards",
                columns: new[] { "MunicipalityId", "JobCardNumber" },
                unique: true,
                filter: "[IsDeleted] = 0");

            migrationBuilder.AddForeignKey(
                name: "FK_JobCards_Municipalities_MunicipalityId",
                table: "JobCards",
                column: "MunicipalityId",
                principalTable: "Municipalities",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_JobCards_Municipalities_MunicipalityId",
                table: "JobCards");

            migrationBuilder.DropIndex(
                name: "IX_JobCards_MunicipalityId_JobCardNumber",
                table: "JobCards");

            migrationBuilder.DropColumn(
                name: "MunicipalityId",
                table: "JobCards");

            migrationBuilder.CreateIndex(
                name: "IX_JobCards_JobCardNumber",
                table: "JobCards",
                column: "JobCardNumber",
                unique: true);
        }
    }
}
