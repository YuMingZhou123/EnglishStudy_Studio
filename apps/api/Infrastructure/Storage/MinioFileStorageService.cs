using Api.Application.Common.Interfaces;
using Api.Infrastructure.Options;
using Microsoft.Extensions.Options;
using Minio;
using Minio.DataModel.Args;

namespace Api.Infrastructure.Storage;

public sealed class MinioFileStorageService(IOptions<StorageOptions> options) : IFileStorageService
{
    public async Task<StoredFileResult> UploadAsync(
        Stream stream,
        string objectKey,
        string contentType,
        long size,
        CancellationToken cancellationToken = default)
    {
        var storageOptions = options.Value;
        var client = CreateClient(storageOptions);
        await EnsureBucketAsync(client, storageOptions.Bucket, cancellationToken);

        var putObjectArgs = new PutObjectArgs()
            .WithBucket(storageOptions.Bucket)
            .WithObject(objectKey)
            .WithStreamData(stream)
            .WithObjectSize(size)
            .WithContentType(contentType);

        await client.PutObjectAsync(putObjectArgs, cancellationToken);

        return new StoredFileResult(
            storageOptions.Bucket,
            objectKey,
            BuildPublicObjectUrl(storageOptions, objectKey),
            contentType,
            size);
    }

    public async Task<StoredReadResult> OpenReadAsync(
        string objectKey,
        CancellationToken cancellationToken = default)
    {
        var storageOptions = options.Value;
        var client = CreateClient(storageOptions);
        var memoryStream = new MemoryStream();

        var getObjectArgs = new GetObjectArgs()
            .WithBucket(storageOptions.Bucket)
            .WithObject(objectKey)
            .WithCallbackStream(stream => stream.CopyTo(memoryStream));

        await client.GetObjectAsync(getObjectArgs, cancellationToken);
        memoryStream.Position = 0;

        return new StoredReadResult(memoryStream, "application/octet-stream", memoryStream.Length);
    }

    private static IMinioClient CreateClient(StorageOptions storageOptions)
    {
        var endpoint = storageOptions.Endpoint;
        var useSsl = storageOptions.UseSSL;
        if ((endpoint.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                endpoint.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) &&
            Uri.TryCreate(endpoint, UriKind.Absolute, out var endpointUri))
        {
            endpoint = endpointUri.Authority;
            useSsl = endpointUri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase);
        }

        var builder = new MinioClient()
            .WithEndpoint(endpoint)
            .WithCredentials(storageOptions.AccessKey, storageOptions.SecretKey);

        if (useSsl)
        {
            builder = builder.WithSSL();
        }

        return builder.Build();
    }

    private static async Task EnsureBucketAsync(
        IMinioClient client,
        string bucket,
        CancellationToken cancellationToken)
    {
        var exists = await client.BucketExistsAsync(
            new BucketExistsArgs().WithBucket(bucket),
            cancellationToken);

        if (exists)
        {
            return;
        }

        await client.MakeBucketAsync(
            new MakeBucketArgs().WithBucket(bucket),
            cancellationToken);
    }

    private static string BuildPublicObjectUrl(StorageOptions storageOptions, string objectKey)
    {
        var baseUrl = storageOptions.PublicApiBaseUrl.TrimEnd('/');
        return $"{baseUrl}/api/media/objects/{objectKey}";
    }
}
