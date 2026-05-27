using Api.Data;
using Api.Entities;
using Api.Options;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Default")));
builder.Services.AddIdentityCore<ApplicationUser>()
    .AddRoles<ApplicationRole>()
    .AddEntityFrameworkStores<AppDbContext>();
builder.Services.Configure<StorageOptions>(
    builder.Configuration.GetSection(StorageOptions.SectionName));
builder.Services.AddHttpClient();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

app.UseAuthorization();

app.MapControllers();
app.MapGet("/health", () => Results.Ok(new
{
    status = "Healthy",
    service = "EnglishStudy Studio API",
    checkedAt = DateTimeOffset.UtcNow
}));

app.MapGet("/health/ready", async (
    AppDbContext db,
    IOptions<StorageOptions> storageOptions,
    IHttpClientFactory httpClientFactory,
    CancellationToken cancellationToken) =>
{
    var checks = new Dictionary<string, string>();

    try
    {
        checks["database"] = await db.Database.CanConnectAsync(cancellationToken)
            ? "Healthy"
            : "Unhealthy";
    }
    catch (Exception ex)
    {
        checks["database"] = $"Unhealthy: {ex.GetType().Name}";
    }

    try
    {
        using var client = httpClientFactory.CreateClient();
        client.Timeout = TimeSpan.FromSeconds(3);

        var storageEndpoint = storageOptions.Value.GetEndpointUri();
        var healthUri = new Uri(storageEndpoint, "/minio/health/live");
        using var response = await client.GetAsync(healthUri, cancellationToken);

        checks["storage"] = response.IsSuccessStatusCode
            ? "Healthy"
            : $"Unhealthy: {(int)response.StatusCode}";
    }
    catch (Exception ex)
    {
        checks["storage"] = $"Unhealthy: {ex.GetType().Name}";
    }

    var ready = checks.Values.All(value => value == "Healthy");
    var payload = new
    {
        status = ready ? "Healthy" : "Unhealthy",
        checks,
        checkedAt = DateTimeOffset.UtcNow
    };

    return ready
        ? Results.Ok(payload)
        : Results.Json(payload, statusCode: StatusCodes.Status503ServiceUnavailable);
});

app.Run();
