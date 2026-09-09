using DriveOp.Api.Entities;
using DriveOp.Api.Entities.Common;
using Microsoft.EntityFrameworkCore;

namespace DriveOp.Api.Data
{
    public class DriveOpDbContext : DbContext
    {
        public DriveOpDbContext(DbContextOptions<DriveOpDbContext> options) : base(options)
        {

        }

        public DbSet<Municipality> Municipalities => Set<Municipality>();
        public DbSet<Vehicle> Vehicles => Set<Vehicle>();
        public DbSet<Driver> Drivers => Set<Driver>();
        public DbSet<Supervisor> Supervisors => Set<Supervisor>();
        public DbSet<Mechanic> Mechanics => Set<Mechanic>();
        public DbSet<Incident> Incidents => Set<Incident>();
        public DbSet<JobCard> JobCards => Set<JobCard>();

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);
            modelBuilder.ApplyConfigurationsFromAssembly(typeof(DriveOpDbContext).Assembly);

            foreach (var entityType in modelBuilder.Model.GetEntityTypes()
                .Where(e => typeof(BaseEntity).IsAssignableFrom(e.ClrType)))
            {
                modelBuilder.Entity(entityType.ClrType)
                    .Property(nameof(BaseEntity.RowVersion))
                    .IsRowVersion();
            }
        }

        public override int SaveChanges(bool acceptAllChangesOnSuccess)
        {
            ApplyAuditRules();
            return base.SaveChanges(acceptAllChangesOnSuccess);
        }

        public override Task<int> SaveChangesAsync(bool acceptAllChangesOnSuccess, CancellationToken cancellationToken = default)
        {
            ApplyAuditRules();
            return base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
        }

        private void ApplyAuditRules()
        {
            var now = DateTime.UtcNow;

            foreach (var entry in ChangeTracker.Entries<IAuditable>().ToList())
            {
                switch (entry.State)
                {
                    case EntityState.Added:
                        entry.Entity.CreatedAt = now;
                        break;

                    case EntityState.Modified:
                        entry.Entity.UpdatedAt = now;
                        break;
                }
            }

            foreach (var entry in ChangeTracker.Entries<ISoftDeletable>().ToList())
            {
                if (entry.State != EntityState.Deleted)
                    continue;

                entry.State = EntityState.Unchanged;
                entry.Entity.IsDeleted = true;
                entry.Entity.DeletedAt = now;
                entry.Property(nameof(ISoftDeletable.IsDeleted)).IsModified = true;
                entry.Property(nameof(ISoftDeletable.DeletedAt)).IsModified = true;
            }
        }
    }
}
