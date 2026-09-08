using DriveOp.Api.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DriveOp.Api.Data.Configurations
{
    public class JobCardConfiguration : IEntityTypeConfiguration<JobCard>
    {
        public void Configure(EntityTypeBuilder<JobCard> builder)
        {
            builder.HasKey(j => j.Id);

            builder.Property(j => j.JobCardNumber).IsRequired().HasMaxLength(50);
            builder.Property(j => j.Notes).HasMaxLength(4000);

            builder.HasIndex(j => new { j.MunicipalityId, j.JobCardNumber })
                .IsUnique()
                .HasFilter("[IsDeleted] = 0");

            builder.HasOne(j => j.Municipality)
                .WithMany(m => m.JobCards)
                .HasForeignKey(j => j.MunicipalityId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasOne(j => j.Incident)
                .WithOne(i => i.JobCard)
                .HasForeignKey<JobCard>(j => j.IncidentId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasOne(j => j.AssignedSupervisor)
                .WithMany(s => s.JobCards)
                .HasForeignKey(j => j.AssignedSupervisorId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasOne(j => j.AssignedMechanic)
                .WithMany(m => m.JobCards)
                .HasForeignKey(j => j.AssignedMechanicId)
                .OnDelete(DeleteBehavior.Restrict);

            builder.HasQueryFilter(j => !j.IsDeleted);
        }
    }
}
