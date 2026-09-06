using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DriveOp.Api.Data.Configurations
{
    public class DriverConfiguration : IEntityTypeConfiguration<Driver>
    {
        public void Configure(EntityTypeBuilder<Driver> builder)
        {
            builder.HasKey(d => d.Id);

            builder.Property(d => d.Name).IsRequired().HasMaxLength(100);
            builder.Property(d => d.Surname).IsRequired().HasMaxLength(100);
            builder.Property(d => d.LicenseNumber).IsRequired().HasMaxLength(50);

            builder.HasIndex(d => d.LicenseNumber).IsUnique();

            builder.HasOne(d => d.Municipality)
                .WithMany(m => m.Drivers)
                .HasForeignKey(d => d.MunicipalityId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasQueryFilter(d => !d.IsDeleted);
        }
    }
}
