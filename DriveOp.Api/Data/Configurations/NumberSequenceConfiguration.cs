using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DriveOp.Api.Data.Configurations
{
    public class NumberSequenceConfiguration : IEntityTypeConfiguration<NumberSequence>
    {
        public void Configure(EntityTypeBuilder<NumberSequence> builder)
        {

            builder.ToTable("NumberSequences");

            builder.HasKey(n => new { n.MunicipalityId, n.SequenceName, n.PeriodKey });

            builder.Property(n => n.SequenceName).IsRequired().HasMaxLength(50);
            builder.Property(n => n.PeriodKey).IsRequired().HasMaxLength(20);

            // No query filter: this is infrastructure, not domain data, and is never
            // soft-deleted. EF Core warns that Municipality's filter and this required
            // navigation could interact badly, but nothing ever Includes Municipality
            // from a sequence — the allocator works from the composite key alone.

            builder.HasOne(n => n.Municipality)
                .WithMany(m => m.NumberSequences)
                .HasForeignKey(n => n.MunicipalityId)
                .OnDelete(DeleteBehavior.Restrict);
        }
    }
}
