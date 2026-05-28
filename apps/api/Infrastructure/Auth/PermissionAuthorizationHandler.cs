using System.Security.Claims;
using Api.Domain.Identity;
using Api.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;

namespace Api.Infrastructure.Auth;

public sealed class PermissionAuthorizationHandler(AppDbContext dbContext)
    : AuthorizationHandler<PermissionAuthorizationRequirement>
{
    protected override async Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        PermissionAuthorizationRequirement requirement)
    {
        if (context.User.Identity?.IsAuthenticated != true)
        {
            return;
        }

        var userIdValue = context.User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!Guid.TryParse(userIdValue, out var userId))
        {
            return;
        }

        var hasPermission = await dbContext.Set<ApplicationUserRole>()
            .Where(userRole => userRole.UserId == userId)
            .Join(
                dbContext.RolePermissions,
                userRole => userRole.RoleId,
                rolePermission => rolePermission.RoleId,
                (_, rolePermission) => rolePermission)
            .AnyAsync(rolePermission =>
                rolePermission.Permission.Code == requirement.PermissionCode &&
                rolePermission.Permission.IsEnabled);

        if (hasPermission)
        {
            context.Succeed(requirement);
        }
    }
}
