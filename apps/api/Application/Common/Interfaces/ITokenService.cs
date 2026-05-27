using Api.Domain.Identity;

namespace Api.Application.Common.Interfaces;

public interface ITokenService
{
    TokenResult CreateToken(ApplicationUser user, IReadOnlyCollection<string> roles);
}

public sealed record TokenResult(
    string AccessToken,
    DateTimeOffset ExpiresAt);
