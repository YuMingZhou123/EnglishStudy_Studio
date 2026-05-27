using Api.Application.Auth;
using Api.Application.Dictation;
using Microsoft.Extensions.DependencyInjection;

namespace Api.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<IDictationService, DictationService>();

        return services;
    }
}
