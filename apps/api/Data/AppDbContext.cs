using Api.Entities;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options)
    : IdentityDbContext<
        ApplicationUser,
        ApplicationRole,
        Guid,
        IdentityUserClaim<Guid>,
        ApplicationUserRole,
        IdentityUserLogin<Guid>,
        IdentityRoleClaim<Guid>,
        IdentityUserToken<Guid>>(options)
{
    public DbSet<Permission> Permissions => Set<Permission>();

    public DbSet<RolePermission> RolePermissions => Set<RolePermission>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.HasDefaultSchema("public");

        ConfigureIdentityTables(modelBuilder);
        ConfigurePermissionTables(modelBuilder);
    }

    private static void ConfigureIdentityTables(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ApplicationUser>(entity =>
        {
            entity.ToTable("users");
            entity.Property(user => user.DisplayName).HasMaxLength(128);
            entity.Property(user => user.AvatarUrl).HasMaxLength(512);
            entity.Property(user => user.CurrentLevel).HasMaxLength(32);
            entity.Property(user => user.LearningGoal).HasMaxLength(64);
            entity.Property(user => user.MembershipStatus).HasMaxLength(32);
        });

        modelBuilder.Entity<ApplicationRole>(entity =>
        {
            entity.ToTable("roles");
            entity.Property(role => role.Description).HasMaxLength(512);
        });

        modelBuilder.Entity<ApplicationUserRole>(entity =>
        {
            entity.ToTable("user_roles");
            entity.HasKey(userRole => new { userRole.UserId, userRole.RoleId });

            entity.HasOne(userRole => userRole.User)
                .WithMany(user => user.UserRoles)
                .HasForeignKey(userRole => userRole.UserId)
                .IsRequired();

            entity.HasOne(userRole => userRole.Role)
                .WithMany(role => role.UserRoles)
                .HasForeignKey(userRole => userRole.RoleId)
                .IsRequired();
        });

        modelBuilder.Entity<IdentityUserClaim<Guid>>().ToTable("user_claims");
        modelBuilder.Entity<IdentityRoleClaim<Guid>>().ToTable("role_claims");
        modelBuilder.Entity<IdentityUserLogin<Guid>>().ToTable("user_logins");
        modelBuilder.Entity<IdentityUserToken<Guid>>().ToTable("user_tokens");
    }

    private static void ConfigurePermissionTables(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Permission>(entity =>
        {
            entity.ToTable("permissions");
            entity.HasKey(permission => permission.Id);
            entity.HasIndex(permission => permission.Code).IsUnique();

            entity.Property(permission => permission.Code).HasMaxLength(128).IsRequired();
            entity.Property(permission => permission.Name).HasMaxLength(128).IsRequired();
            entity.Property(permission => permission.Module).HasMaxLength(64).IsRequired();
            entity.Property(permission => permission.Resource).HasMaxLength(64).IsRequired();
            entity.Property(permission => permission.Action).HasMaxLength(64).IsRequired();
            entity.Property(permission => permission.Type).HasMaxLength(32).IsRequired();
            entity.Property(permission => permission.Description).HasMaxLength(512);
        });

        modelBuilder.Entity<RolePermission>(entity =>
        {
            entity.ToTable("role_permissions");
            entity.HasKey(rolePermission => new
            {
                rolePermission.RoleId,
                rolePermission.PermissionId
            });

            entity.HasOne(rolePermission => rolePermission.Role)
                .WithMany(role => role.RolePermissions)
                .HasForeignKey(rolePermission => rolePermission.RoleId)
                .IsRequired();

            entity.HasOne(rolePermission => rolePermission.Permission)
                .WithMany(permission => permission.RolePermissions)
                .HasForeignKey(rolePermission => rolePermission.PermissionId)
                .IsRequired();
        });
    }
}
