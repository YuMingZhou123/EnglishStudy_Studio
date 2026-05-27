namespace Api.Entities;

public sealed class Permission
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public string Code { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    public string Module { get; set; } = string.Empty;

    public string Resource { get; set; } = string.Empty;

    public string Action { get; set; } = string.Empty;

    public string Type { get; set; } = "api";

    public string? Description { get; set; }

    public bool IsEnabled { get; set; } = true;

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public ICollection<RolePermission> RolePermissions { get; } = new List<RolePermission>();
}

