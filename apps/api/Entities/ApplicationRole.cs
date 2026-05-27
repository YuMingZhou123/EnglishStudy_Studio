using Microsoft.AspNetCore.Identity;

namespace Api.Entities;

public sealed class ApplicationRole : IdentityRole<Guid>
{
    public string? Description { get; set; }

    public bool IsSystem { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public ICollection<ApplicationUserRole> UserRoles { get; } = new List<ApplicationUserRole>();

    public ICollection<RolePermission> RolePermissions { get; } = new List<RolePermission>();
}

