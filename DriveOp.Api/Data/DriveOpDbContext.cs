using Microsoft.EntityFrameworkCore;

namespace DriveOp.Api.Data
{
    public class DriveOpDbContext : DbContext
    {
        public DriveOpDbContext(DbContextOptions<DriveOpDbContext> options) : base(options)
        {

        }
    }
}
