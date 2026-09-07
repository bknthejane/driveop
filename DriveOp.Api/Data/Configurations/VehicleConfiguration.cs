using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DriveOp.Api.Data.Configurations
{
    public class VehicleConfiguration : IEntityTypeConfiguration<Vehicle>
    {
        public void Configure(EntityTypeBuilder<Vehicle> builder)
        {
            builder.HasKey(v => v.Id);

            builder.Property(v => v.FleetNumber).IsRequired().HasMaxLength(50);
            builder.Property(v => v.RegistrationNumber).IsRequired().HasMaxLength(20);
            builder.Property(v => v.Make).IsRequired().HasMaxLength(100);
            builder.Property(v => v.Model).IsRequired().HasMaxLength(100);

            builder.HasIndex(v => new { v.MunicipalityId, v.FleetNumber })
                .IsUnique()
                .HasFilter("[IsDeleted] = 0");

            builder.HasIndex(v => v.RegistrationNumber)
                .IsUnique()
                .HasFilter("[IsDeleted] = 0");

            builder.HasOne(v => v.Municipality)
                .WithMany(m => m.Vehicles)
                .HasForeignKey(v => v.MunicipalityId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasOne(v => v.AssignedDriver)
                .WithMany(d => d.AssignedVehicles)
                .HasForeignKey(v => v.AssignedDriverId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasQueryFilter(v => !v.IsDeleted);
        }
    }
}
