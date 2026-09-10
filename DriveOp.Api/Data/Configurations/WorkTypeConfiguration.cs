using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DriveOp.Api.Data.Configurations
{
    public class WorkTypeConfiguration : IEntityTypeConfiguration<WorkType>
    {
        public void Configure(EntityTypeBuilder<WorkType> builder)
        {
            builder.HasKey(w => w.Id);

            builder.Property(w => w.Name).IsRequired().HasMaxLength(100);

            builder.HasIndex(w => new { w.MunicipalityId, w.Name })
                .IsUnique()
                .HasFilter("[IsDeleted] = 0");

            builder.HasIndex(w => w.DepartmentId);

            builder.HasOne(w => w.Municipality)
                .WithMany(m => m.WorkTypes)
                .HasForeignKey(w => w.MunicipalityId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasOne(w => w.Department)
                .WithMany(d => d.WorkTypes)
                .HasForeignKey(w => w.DepartmentId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasQueryFilter(w => !w.IsDeleted);
        }
    }
}
