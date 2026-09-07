using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DriveOp.Api.Migrations
{
    /// <inheritdoc />
    public partial class TenantScopedFleetNumberIndexes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Vehicles_FleetNumber",
                table: "Vehicles");

            migrationBuilder.DropIndex(
                name: "IX_Vehicles_MunicipalityId",
                table: "Vehicles");

            migrationBuilder.DropIndex(
                name: "IX_Vehicles_RegistrationNumber",
                table: "Vehicles");

            migrationBuilder.CreateIndex(
                name: "IX_Vehicles_MunicipalityId_FleetNumber",
                table: "Vehicles",
                columns: new[] { "MunicipalityId", "FleetNumber" },
                unique: true,
                filter: "[IsDeleted] = 0");

            migrationBuilder.CreateIndex(
                name: "IX_Vehicles_RegistrationNumber",
                table: "Vehicles",
                column: "RegistrationNumber",
                unique: true,
                filter: "[IsDeleted] = 0");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Vehicles_MunicipalityId_FleetNumber",
                table: "Vehicles");

            migrationBuilder.DropIndex(
                name: "IX_Vehicles_RegistrationNumber",
                table: "Vehicles");

            migrationBuilder.CreateIndex(
                name: "IX_Vehicles_FleetNumber",
                table: "Vehicles",
                column: "FleetNumber",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Vehicles_MunicipalityId",
                table: "Vehicles",
                column: "MunicipalityId");

            migrationBuilder.CreateIndex(
                name: "IX_Vehicles_RegistrationNumber",
                table: "Vehicles",
                column: "RegistrationNumber",
                unique: true);
        }
    }
}
