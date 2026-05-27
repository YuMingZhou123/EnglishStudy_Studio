using Api.Domain.Content;
using Api.Domain.Identity;
using Api.Domain.Learning;
using Microsoft.EntityFrameworkCore;

namespace Api.Application.Common.Interfaces;

public interface IAppDbContext
{
    DbSet<Permission> Permissions { get; }

    DbSet<RolePermission> RolePermissions { get; }

    DbSet<Scene> Scenes { get; }

    DbSet<Word> Words { get; }

    DbSet<MediaAsset> MediaAssets { get; }

    DbSet<Sentence> Sentences { get; }

    DbSet<SentenceKeyword> SentenceKeywords { get; }

    DbSet<DictationAttempt> DictationAttempts { get; }

    DbSet<UserWordState> UserWordStates { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
