using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DriveOp.Api.Data.Configurations
{
    public class IncidentConfiguration : IEntityTypeConfiguration<Incident>
    {
        public void Configure(EntityTypeBuilder<Incident> builder)
        {
            builder.HasKey(i => i.Id);

            builder.Property(i => i.Description).IsRequired().HasMaxLength(4000);

            builder.HasOne(i => i.Vehicle)
                .WithMany(v => v.Incidents)
                .HasForeignKey(i => i.VehicleId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasOne(i => i.Driver)
                .WithMany(d => d.Incidents)
                .HasForeignKey(i => i.DriverId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasQueryFilter(i => !i.IsDeleted);
        }
    }
}
