using Microsoft.AspNetCore.Authorization;

namespace Api.Infrastructure.Auth;

public sealed class PermissionAuthorizationRequirement(string permissionCode)
    : IAuthorizationRequirement
{
    public string PermissionCode { get; } = permissionCode;
}
