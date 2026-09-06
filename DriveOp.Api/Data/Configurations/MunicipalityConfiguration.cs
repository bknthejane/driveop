using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DriveOp.Api.Data.Configurations
{
    public class MunicipalityConfiguration : IEntityTypeConfiguration<Municipality>
    {
        public void Configure(EntityTypeBuilder<Municipality> builder)
        {
            builder.HasKey(m => m.Id);

            builder.Property(m => m.Name).IsRequired().HasMaxLength(200);
            builder.Property(m => m.Code).IsRequired().HasMaxLength(20);
            builder.Property(m => m.Province).HasMaxLength(100);

            builder.HasIndex(m => m.Code).IsUnique();

            builder.HasQueryFilter(m => !m.IsDeleted);
        }
    }
}
