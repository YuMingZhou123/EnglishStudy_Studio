using Api.Application.Auth;
using Api.Application.Content;
using Api.Application.Dictation;
using Api.Application.Media;
using Microsoft.Extensions.DependencyInjection;

namespace Api.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<IContentAdminService, ContentAdminService>();
        services.AddScoped<IDictationService, DictationService>();
        services.AddScoped<IMediaService, MediaService>();

        return services;
    }
}
