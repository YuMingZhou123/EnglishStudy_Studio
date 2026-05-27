using Microsoft.AspNetCore.Identity;

namespace Api.Domain.Identity;

public sealed class ApplicationUserRole : IdentityUserRole<Guid>
{
    public DateTimeOffset AssignedAt { get; set; } = DateTimeOffset.UtcNow;

    public ApplicationUser User { get; set; } = null!;

    public ApplicationRole Role { get; set; } = null!;
}
