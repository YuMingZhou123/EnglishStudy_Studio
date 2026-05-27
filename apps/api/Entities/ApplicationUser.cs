using Microsoft.AspNetCore.Identity;

namespace Api.Entities;

public sealed class ApplicationUser : IdentityUser<Guid>
{
    public string? DisplayName { get; set; }

    public string? AvatarUrl { get; set; }

    public string? CurrentLevel { get; set; }

    public string? LearningGoal { get; set; }

    public string MembershipStatus { get; set; } = "Free";

    public Guid? OrganizationId { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public ICollection<ApplicationUserRole> UserRoles { get; } = new List<ApplicationUserRole>();
}

