using Api.Application.Common.Interfaces;
using Api.Domain.Content;
using Api.Domain.Identity;
using Api.Domain.Learning;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace Api.Infrastructure.Persistence;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options)
    : IdentityDbContext<
        ApplicationUser,
        ApplicationRole,
        Guid,
        IdentityUserClaim<Guid>,
        ApplicationUserRole,
        IdentityUserLogin<Guid>,
        IdentityRoleClaim<Guid>,
        IdentityUserToken<Guid>>(options), IAppDbContext
{
    public DbSet<Permission> Permissions => Set<Permission>();

    public DbSet<RolePermission> RolePermissions => Set<RolePermission>();

    public DbSet<Scene> Scenes => Set<Scene>();

    public DbSet<Word> Words => Set<Word>();

    public DbSet<MediaAsset> MediaAssets => Set<MediaAsset>();

    public DbSet<Sentence> Sentences => Set<Sentence>();

    public DbSet<SentenceKeyword> SentenceKeywords => Set<SentenceKeyword>();

    public DbSet<DictationAttempt> DictationAttempts => Set<DictationAttempt>();

    public DbSet<UserWordState> UserWordStates => Set<UserWordState>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.HasDefaultSchema("public");

        ConfigureIdentityTables(modelBuilder);
        ConfigurePermissionTables(modelBuilder);
        ConfigureContentTables(modelBuilder);
        ConfigureLearningTables(modelBuilder);
    }

    private static void ConfigureIdentityTables(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ApplicationUser>(entity =>
        {
            entity.ToTable("users");
            entity.Property(user => user.DisplayName).HasMaxLength(128);
            entity.Property(user => user.AvatarUrl).HasMaxLength(512);
            entity.Property(user => user.CurrentLevel).HasMaxLength(32);
            entity.Property(user => user.LearningGoal).HasMaxLength(64);
            entity.Property(user => user.MembershipStatus).HasMaxLength(32);
        });

        modelBuilder.Entity<ApplicationRole>(entity =>
        {
            entity.ToTable("roles");
            entity.Property(role => role.Description).HasMaxLength(512);
        });

        modelBuilder.Entity<ApplicationUserRole>(entity =>
        {
            entity.ToTable("user_roles");
            entity.HasKey(userRole => new { userRole.UserId, userRole.RoleId });

            entity.HasOne(userRole => userRole.User)
                .WithMany(user => user.UserRoles)
                .HasForeignKey(userRole => userRole.UserId)
                .IsRequired();

            entity.HasOne(userRole => userRole.Role)
                .WithMany(role => role.UserRoles)
                .HasForeignKey(userRole => userRole.RoleId)
                .IsRequired();
        });

        modelBuilder.Entity<IdentityUserClaim<Guid>>().ToTable("user_claims");
        modelBuilder.Entity<IdentityRoleClaim<Guid>>().ToTable("role_claims");
        modelBuilder.Entity<IdentityUserLogin<Guid>>().ToTable("user_logins");
        modelBuilder.Entity<IdentityUserToken<Guid>>().ToTable("user_tokens");
    }

    private static void ConfigurePermissionTables(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Permission>(entity =>
        {
            entity.ToTable("permissions");
            entity.HasKey(permission => permission.Id);
            entity.HasIndex(permission => permission.Code).IsUnique();

            entity.Property(permission => permission.Code).HasMaxLength(128).IsRequired();
            entity.Property(permission => permission.Name).HasMaxLength(128).IsRequired();
            entity.Property(permission => permission.Module).HasMaxLength(64).IsRequired();
            entity.Property(permission => permission.Resource).HasMaxLength(64).IsRequired();
            entity.Property(permission => permission.Action).HasMaxLength(64).IsRequired();
            entity.Property(permission => permission.Type).HasMaxLength(32).IsRequired();
            entity.Property(permission => permission.Description).HasMaxLength(512);
        });

        modelBuilder.Entity<RolePermission>(entity =>
        {
            entity.ToTable("role_permissions");
            entity.HasKey(rolePermission => new
            {
                rolePermission.RoleId,
                rolePermission.PermissionId
            });

            entity.HasOne(rolePermission => rolePermission.Role)
                .WithMany(role => role.RolePermissions)
                .HasForeignKey(rolePermission => rolePermission.RoleId)
                .IsRequired();

            entity.HasOne(rolePermission => rolePermission.Permission)
                .WithMany(permission => permission.RolePermissions)
                .HasForeignKey(rolePermission => rolePermission.PermissionId)
                .IsRequired();
        });
    }

    private static void ConfigureContentTables(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Scene>(entity =>
        {
            entity.ToTable("scenes");
            entity.HasKey(scene => scene.Id);
            entity.HasIndex(scene => scene.Code).IsUnique();

            entity.Property(scene => scene.Code).HasMaxLength(64).IsRequired();
            entity.Property(scene => scene.Name).HasMaxLength(128).IsRequired();
            entity.Property(scene => scene.Description).HasMaxLength(512);
        });

        modelBuilder.Entity<Word>(entity =>
        {
            entity.ToTable("words");
            entity.HasKey(word => word.Id);
            entity.HasIndex(word => word.Lemma).IsUnique();

            entity.Property(word => word.Lemma).HasMaxLength(128).IsRequired();
            entity.Property(word => word.Phonetic).HasMaxLength(64);
            entity.Property(word => word.PartOfSpeech).HasMaxLength(64);
            entity.Property(word => word.MeaningCn).HasMaxLength(512).IsRequired();
            entity.Property(word => word.CefrLevel).HasMaxLength(32);
            entity.Property(word => word.ExamTags).HasMaxLength(256);
            entity.Property(word => word.Collocations).HasMaxLength(1024);
        });

        modelBuilder.Entity<MediaAsset>(entity =>
        {
            entity.ToTable("media_assets");
            entity.HasKey(asset => asset.Id);
            entity.HasIndex(asset => new { asset.Bucket, asset.ObjectKey }).IsUnique();

            entity.Property(asset => asset.Bucket).HasMaxLength(128).IsRequired();
            entity.Property(asset => asset.ObjectKey).HasMaxLength(512).IsRequired();
            entity.Property(asset => asset.Url).HasMaxLength(1024).IsRequired();
            entity.Property(asset => asset.ContentType).HasMaxLength(128).IsRequired();
            entity.Property(asset => asset.Source).HasMaxLength(32).IsRequired();
        });

        modelBuilder.Entity<Sentence>(entity =>
        {
            entity.ToTable("sentences");
            entity.HasKey(sentence => sentence.Id);
            entity.HasIndex(sentence => new { sentence.Level, sentence.Status });
            entity.HasIndex(sentence => sentence.SceneId);

            entity.Property(sentence => sentence.Text).HasMaxLength(1024).IsRequired();
            entity.Property(sentence => sentence.Translation).HasMaxLength(1024).IsRequired();
            entity.Property(sentence => sentence.Level).HasMaxLength(32).IsRequired();
            entity.Property(sentence => sentence.AudioUrl).HasMaxLength(1024);
            entity.Property(sentence => sentence.SlowAudioUrl).HasMaxLength(1024);
            entity.Property(sentence => sentence.Source).HasMaxLength(32).IsRequired();
            entity.Property(sentence => sentence.Status).HasMaxLength(32).IsRequired();

            entity.HasOne(sentence => sentence.Scene)
                .WithMany(scene => scene.Sentences)
                .HasForeignKey(sentence => sentence.SceneId)
                .IsRequired();

            entity.HasOne(sentence => sentence.AudioAsset)
                .WithMany()
                .HasForeignKey(sentence => sentence.AudioAssetId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<SentenceKeyword>(entity =>
        {
            entity.ToTable("sentence_keywords");
            entity.HasKey(keyword => keyword.Id);
            entity.HasIndex(keyword => keyword.SentenceId);
            entity.HasIndex(keyword => keyword.WordId);

            entity.Property(keyword => keyword.SurfaceText).HasMaxLength(128).IsRequired();
            entity.Property(keyword => keyword.BlankGroup).HasMaxLength(128);

            entity.HasOne(keyword => keyword.Sentence)
                .WithMany(sentence => sentence.Keywords)
                .HasForeignKey(keyword => keyword.SentenceId)
                .IsRequired();

            entity.HasOne(keyword => keyword.Word)
                .WithMany(word => word.SentenceKeywords)
                .HasForeignKey(keyword => keyword.WordId)
                .OnDelete(DeleteBehavior.Restrict)
                .IsRequired();
        });
    }

    private static void ConfigureLearningTables(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<DictationAttempt>(entity =>
        {
            entity.ToTable("dictation_attempts");
            entity.HasKey(attempt => attempt.Id);
            entity.HasIndex(attempt => new { attempt.UserId, attempt.CreatedAt });
            entity.HasIndex(attempt => attempt.SentenceId);

            entity.Property(attempt => attempt.Mode).HasMaxLength(32).IsRequired();
            entity.Property(attempt => attempt.UserAnswer).HasMaxLength(2048).IsRequired();
            entity.Property(attempt => attempt.NormalizedAnswer).HasMaxLength(2048).IsRequired();
            entity.Property(attempt => attempt.DetailJson).HasColumnType("jsonb");

            entity.HasOne(attempt => attempt.User)
                .WithMany()
                .HasForeignKey(attempt => attempt.UserId)
                .IsRequired();

            entity.HasOne(attempt => attempt.Sentence)
                .WithMany(sentence => sentence.DictationAttempts)
                .HasForeignKey(attempt => attempt.SentenceId)
                .IsRequired();
        });

        modelBuilder.Entity<UserWordState>(entity =>
        {
            entity.ToTable("user_word_states");
            entity.HasKey(state => state.Id);
            entity.HasIndex(state => new { state.UserId, state.WordId }).IsUnique();
            entity.HasIndex(state => state.NextReviewAt);

            entity.Property(state => state.Status).HasMaxLength(32).IsRequired();
            entity.Property(state => state.Source).HasMaxLength(32).IsRequired();

            entity.HasOne(state => state.User)
                .WithMany()
                .HasForeignKey(state => state.UserId)
                .IsRequired();

            entity.HasOne(state => state.Word)
                .WithMany()
                .HasForeignKey(state => state.WordId)
                .OnDelete(DeleteBehavior.Restrict)
                .IsRequired();
        });
    }
}
