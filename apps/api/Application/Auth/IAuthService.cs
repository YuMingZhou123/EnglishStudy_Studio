namespace Api.Application.Auth;

public interface IAuthService
{
    Task<ServiceResult<AuthResponse>> RegisterAsync(
        RegisterRequest request,
        CancellationToken cancellationToken = default);

    Task<ServiceResult<AuthResponse>> LoginAsync(
        LoginRequest request,
        CancellationToken cancellationToken = default);

    Task<ServiceResult<CurrentUserResponse>> GetCurrentUserAsync(
        Guid userId,
        CancellationToken cancellationToken = default);

    Task<ServiceResult<CurrentUserResponse>> UpdateCurrentUserAsync(
        Guid userId,
        UpdateCurrentUserRequest request,
        CancellationToken cancellationToken = default);
}
