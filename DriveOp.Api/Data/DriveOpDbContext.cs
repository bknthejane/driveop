using DriveOp.Api.Entities.Common;
using Microsoft.EntityFrameworkCore;

namespace DriveOp.Api.Data
{
    public class DriveOpDbContext : DbContext
    {
        public DriveOpDbContext(DbContextOptions<DriveOpDbContext> options) : base(options)
        {

        }

        public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
        {
            ApplyAuditRules();
            return base.SaveChangesAsync(cancellationToken);
        }

        public override int SaveChanges()
        {
            ApplyAuditRules();
            return base.SaveChanges();
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

                entry.State = EntityState.Modified;
                entry.Entity.IsDeleted = true;
                entry.Entity.DeletedAt = now;
            }

        }
    }
}
