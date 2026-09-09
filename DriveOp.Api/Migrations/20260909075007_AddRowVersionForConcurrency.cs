using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DriveOp.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddRowVersionForConcurrency : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<byte[]>(
                name: "RowVersion",
                table: "Vehicles",
                type: "rowversion",
                rowVersion: true,
                nullable: false,
                defaultValue: new byte[0]);

            migrationBuilder.AddColumn<byte[]>(
                name: "RowVersion",
                table: "Supervisors",
                type: "rowversion",
                rowVersion: true,
                nullable: false,
                defaultValue: new byte[0]);

            migrationBuilder.AddColumn<byte[]>(
                name: "RowVersion",
                table: "Municipalities",
                type: "rowversion",
                rowVersion: true,
                nullable: false,
                defaultValue: new byte[0]);

            migrationBuilder.AddColumn<byte[]>(
                name: "RowVersion",
                table: "Mechanics",
                type: "rowversion",
                rowVersion: true,
                nullable: false,
                defaultValue: new byte[0]);

            migrationBuilder.AddColumn<byte[]>(
                name: "RowVersion",
                table: "JobCards",
                type: "rowversion",
                rowVersion: true,
                nullable: false,
                defaultValue: new byte[0]);

            migrationBuilder.AddColumn<byte[]>(
                name: "RowVersion",
                table: "Incidents",
                type: "rowversion",
                rowVersion: true,
                nullable: false,
                defaultValue: new byte[0]);

            migrationBuilder.AddColumn<byte[]>(
                name: "RowVersion",
                table: "Drivers",
                type: "rowversion",
                rowVersion: true,
                nullable: false,
                defaultValue: new byte[0]);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "RowVersion",
                table: "Vehicles");

            migrationBuilder.DropColumn(
                name: "RowVersion",
                table: "Supervisors");

            migrationBuilder.DropColumn(
                name: "RowVersion",
                table: "Municipalities");

            migrationBuilder.DropColumn(
                name: "RowVersion",
                table: "Mechanics");

            migrationBuilder.DropColumn(
                name: "RowVersion",
                table: "JobCards");

            migrationBuilder.DropColumn(
                name: "RowVersion",
                table: "Incidents");

            migrationBuilder.DropColumn(
                name: "RowVersion",
                table: "Drivers");
        }
    }
}
