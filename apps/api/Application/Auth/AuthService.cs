using Api.Application.Common.Interfaces;
using Api.Domain.Identity;
using Microsoft.AspNetCore.Identity;

namespace Api.Application.Auth;

public sealed class AuthService(
    UserManager<ApplicationUser> userManager,
    RoleManager<ApplicationRole> roleManager,
    ITokenService tokenService) : IAuthService
{
    private const string LearnerRole = "Learner";

    public async Task<ServiceResult<AuthResponse>> RegisterAsync(
        RegisterRequest request,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Email))
        {
            return ServiceResult<AuthResponse>.Failure("Email is required.");
        }

        if (string.IsNullOrWhiteSpace(request.Password))
        {
            return ServiceResult<AuthResponse>.Failure("Password is required.");
        }

        var email = request.Email.Trim();
        var existingUser = await userManager.FindByEmailAsync(email);
        if (existingUser is not null)
        {
            return ServiceResult<AuthResponse>.Failure("Email is already registered.");
        }

        var user = new ApplicationUser
        {
            UserName = email,
            Email = email,
            EmailConfirmed = true,
            DisplayName = string.IsNullOrWhiteSpace(request.DisplayName)
                ? email.Split('@')[0]
                : request.DisplayName.Trim(),
            CurrentLevel = NormalizeLevel(request.CurrentLevel),
            LearningGoal = string.IsNullOrWhiteSpace(request.LearningGoal)
                ? "daily"
                : request.LearningGoal.Trim(),
            MembershipStatus = "Free"
        };

        var createResult = await userManager.CreateAsync(user, request.Password);
        if (!createResult.Succeeded)
        {
            return ServiceResult<AuthResponse>.Failure(
                createResult.Errors.Select(error => error.Description).ToArray());
        }

        await EnsureRoleExistsAsync(LearnerRole);
        await userManager.AddToRoleAsync(user, LearnerRole);

        var response = await CreateAuthResponseAsync(user);
        return ServiceResult<AuthResponse>.Success(response);
    }

    public async Task<ServiceResult<AuthResponse>> LoginAsync(
        LoginRequest request,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Email) ||
            string.IsNullOrWhiteSpace(request.Password))
        {
            return ServiceResult<AuthResponse>.Failure("Email and password are required.");
        }

        var user = await userManager.FindByEmailAsync(request.Email.Trim());
        if (user is null)
        {
            return ServiceResult<AuthResponse>.Failure("Invalid email or password.");
        }

        var passwordValid = await userManager.CheckPasswordAsync(user, request.Password);
        if (!passwordValid)
        {
            return ServiceResult<AuthResponse>.Failure("Invalid email or password.");
        }

        user.UpdatedAt = DateTimeOffset.UtcNow;
        await userManager.UpdateAsync(user);

        var response = await CreateAuthResponseAsync(user);
        return ServiceResult<AuthResponse>.Success(response);
    }

    public async Task<ServiceResult<CurrentUserResponse>> GetCurrentUserAsync(
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        var user = await userManager.FindByIdAsync(userId.ToString());
        if (user is null)
        {
            return ServiceResult<CurrentUserResponse>.Failure("User was not found.");
        }

        var roles = (await userManager.GetRolesAsync(user)).ToArray();
        return ServiceResult<CurrentUserResponse>.Success(MapUser(user, roles));
    }

    private async Task<AuthResponse> CreateAuthResponseAsync(ApplicationUser user)
    {
        var roles = (await userManager.GetRolesAsync(user)).ToArray();
        var token = tokenService.CreateToken(user, roles);
        return new AuthResponse(
            token.AccessToken,
            token.ExpiresAt,
            MapUser(user, roles));
    }

    private async Task EnsureRoleExistsAsync(string roleName)
    {
        if (await roleManager.RoleExistsAsync(roleName))
        {
            return;
        }

        await roleManager.CreateAsync(new ApplicationRole
        {
            Name = roleName,
            NormalizedName = roleName.ToUpperInvariant(),
            Description = "Default learner role",
            IsSystem = true
        });
    }

    private static CurrentUserResponse MapUser(
        ApplicationUser user,
        IReadOnlyCollection<string> roles)
    {
        return new CurrentUserResponse(
            user.Id,
            user.Email ?? string.Empty,
            user.DisplayName,
            user.CurrentLevel,
            user.LearningGoal,
            user.MembershipStatus,
            roles);
    }

    private static string NormalizeLevel(string? level)
    {
        if (string.IsNullOrWhiteSpace(level))
        {
            return "beginner";
        }

        var normalized = level.Trim().ToLowerInvariant();
        return normalized is "beginner" or "intermediate" or "advanced"
            ? normalized
            : "beginner";
    }
}
