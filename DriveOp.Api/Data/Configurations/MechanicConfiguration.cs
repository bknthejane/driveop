using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DriveOp.Api.Data.Configurations
{
    public class MechanicConfiguration : IEntityTypeConfiguration<Mechanic>
    {
        public void Configure(EntityTypeBuilder<Mechanic> builder)
        {
            builder.HasKey(m => m.Id);

            builder.Property(m => m.Name).IsRequired().HasMaxLength(100);
            builder.Property(m => m.Surname).IsRequired().HasMaxLength(100);

            builder.HasOne(m => m.Municipality)
                .WithMany(mun => mun.Mechanics)
                .HasForeignKey(m => m.MunicipalityId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasOne(m => m.Supervisor)
                .WithMany(s => s.Mechanics)
                .HasForeignKey(m => m.SupervisorId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasQueryFilter(m => !m.IsDeleted);
        }
    }
}
