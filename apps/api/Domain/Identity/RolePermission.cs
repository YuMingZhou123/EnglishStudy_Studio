namespace Api.Domain.Identity;

public sealed class RolePermission
{
    public Guid RoleId { get; set; }

    public Guid PermissionId { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public ApplicationRole Role { get; set; } = null!;

    public Permission Permission { get; set; } = null!;
}
