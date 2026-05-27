namespace Api.Application.Auth;

public sealed record RegisterRequest(
    string Email,
    string Password,
    string? DisplayName,
    string? CurrentLevel,
    string? LearningGoal);

public sealed record LoginRequest(
    string Email,
    string Password);

public sealed record UpdateCurrentUserRequest(
    string? DisplayName,
    string? CurrentLevel,
    string? LearningGoal);

public sealed record AuthResponse(
    string AccessToken,
    DateTimeOffset ExpiresAt,
    CurrentUserResponse User);

public sealed record CurrentUserResponse(
    Guid Id,
    string Email,
    string? DisplayName,
    string? CurrentLevel,
    string? LearningGoal,
    string MembershipStatus,
    IReadOnlyCollection<string> Roles);

public sealed record ServiceResult<T>(
    bool Succeeded,
    T? Value,
    IReadOnlyCollection<string> Errors)
{
    public static ServiceResult<T> Success(T value)
    {
        return new ServiceResult<T>(true, value, Array.Empty<string>());
    }

    public static ServiceResult<T> Failure(params string[] errors)
    {
        return new ServiceResult<T>(false, default, errors);
    }
}
