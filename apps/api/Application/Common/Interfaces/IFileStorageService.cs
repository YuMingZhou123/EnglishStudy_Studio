namespace Api.Application.Common.Interfaces;

public interface IFileStorageService
{
    Task<StoredFileResult> UploadAsync(
        Stream stream,
        string objectKey,
        string contentType,
        long size,
        CancellationToken cancellationToken = default);

    Task<StoredReadResult> OpenReadAsync(
        string objectKey,
        CancellationToken cancellationToken = default);
}

public sealed record StoredFileResult(
    string Bucket,
    string ObjectKey,
    string Url,
    string ContentType,
    long Size);

public sealed record StoredReadResult(
    Stream Stream,
    string ContentType,
    long? Size);
