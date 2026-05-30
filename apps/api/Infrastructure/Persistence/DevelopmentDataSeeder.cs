using Api.Application.Auth;
using Api.Domain.Content;
using Api.Domain.Identity;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace Api.Infrastructure.Persistence;

public static class DevelopmentDataSeeder
{
    public static async Task SeedDevelopmentDataAsync(this WebApplication app)
    {
        if (!app.Environment.IsDevelopment())
        {
            return;
        }

        using var scope = app.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await dbContext.Database.MigrateAsync();

        var roleManager = scope.ServiceProvider.GetRequiredService<RoleManager<ApplicationRole>>();
        var userManager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();

        await EnsureRoleAsync(roleManager, "Learner", "Default learner role");
        var adminRole = await EnsureRoleAsync(roleManager, "Admin", "Platform admin role");
        var contentAdminRole = await EnsureRoleAsync(roleManager, "ContentAdmin", "Content management role");
        var superAdminRole = await EnsureRoleAsync(roleManager, "SuperAdmin", "Platform super admin role");

        var contentManagePermission = await EnsurePermissionAsync(
            dbContext,
            AppPermissions.ContentManage,
            "Manage content",
            "content",
            "content",
            "manage",
            "Create, update, publish, import, and attach media for learning content.");

        await EnsureRolePermissionAsync(dbContext, adminRole, contentManagePermission);
        await EnsureRolePermissionAsync(dbContext, contentAdminRole, contentManagePermission);
        await EnsureRolePermissionAsync(dbContext, superAdminRole, contentManagePermission);
        await dbContext.SaveChangesAsync();

        await EnsureUserAsync(
            userManager,
            "learner@example.com",
            "Pass123$",
            "Demo Learner",
            "Learner");

        await EnsureUserAsync(
            userManager,
            "admin@example.com",
            "Admin123$",
            "Demo Admin",
            "Admin");

        if (await dbContext.Sentences.AnyAsync())
        {
            return;
        }

        var everyday = new Scene
        {
            Code = "daily",
            Name = "Daily English",
            Description = "Short sentences for daily communication."
        };
        var campus = new Scene
        {
            Code = "campus",
            Name = "Campus",
            Description = "Study and campus life."
        };
        var workplace = new Scene
        {
            Code = "workplace",
            Name = "Workplace",
            Description = "Basic workplace communication."
        };
        var travel = new Scene
        {
            Code = "travel",
            Name = "Travel",
            Description = "Travel and life services."
        };

        var words = new Dictionary<string, Word>(StringComparer.OrdinalIgnoreCase)
        {
            ["schedule"] = Word("schedule", "/ˈskedʒuːl/", "verb", "安排"),
            ["meeting"] = Word("meeting", "/ˈmiːtɪŋ/", "noun", "会议"),
            ["marketing"] = Word("marketing", "/ˈmɑːrkɪtɪŋ/", "noun", "市场营销"),
            ["subway"] = Word("subway", "/ˈsʌbweɪ/", "noun", "地铁"),
            ["crowded"] = Word("crowded", "/ˈkraʊdɪd/", "adjective", "拥挤的"),
            ["explain"] = Word("explain", "/ɪkˈspleɪn/", "verb", "解释"),
            ["assignment"] = Word("assignment", "/əˈsaɪnmənt/", "noun", "作业；任务"),
            ["interview"] = Word("interview", "/ˈɪntərvjuː/", "noun", "面试"),
            ["confidence"] = Word("confidence", "/ˈkɑːnfɪdəns/", "noun", "信心"),
            ["reservation"] = Word("reservation", "/ˌrezərˈveɪʃn/", "noun", "预订"),
            ["luggage"] = Word("luggage", "/ˈlʌɡɪdʒ/", "noun", "行李"),
            ["delayed"] = Word("delay", "/dɪˈleɪ/", "verb", "延误")
        };

        dbContext.Scenes.AddRange(everyday, campus, workplace, travel);
        dbContext.Words.AddRange(words.Values);

        AddSentence(
            dbContext,
            workplace,
            "beginner",
            "I need to schedule a meeting with the marketing team.",
            "我需要安排一次与市场团队的会议。",
            (words["schedule"], "schedule", 100),
            (words["meeting"], "meeting", 80),
            (words["marketing"], "marketing", 60));

        AddSentence(
            dbContext,
            everyday,
            "beginner",
            "The subway was crowded during rush hour.",
            "高峰时段地铁很拥挤。",
            (words["subway"], "subway", 100),
            (words["crowded"], "crowded", 90));

        AddSentence(
            dbContext,
            campus,
            "intermediate",
            "Could you explain the assignment before Friday?",
            "你能在周五之前解释一下这个作业吗？",
            (words["explain"], "explain", 100),
            (words["assignment"], "assignment", 90));

        AddSentence(
            dbContext,
            workplace,
            "intermediate",
            "She answered the interview questions with confidence.",
            "她自信地回答了面试问题。",
            (words["interview"], "interview", 100),
            (words["confidence"], "confidence", 90));

        AddSentence(
            dbContext,
            travel,
            "advanced",
            "We changed our reservation because the luggage was delayed.",
            "因为行李延误了，我们更改了预订。",
            (words["reservation"], "reservation", 100),
            (words["luggage"], "luggage", 90),
            (words["delayed"], "delayed", 80));

        await dbContext.SaveChangesAsync();
    }

    private static async Task<ApplicationRole> EnsureRoleAsync(
        RoleManager<ApplicationRole> roleManager,
        string name,
        string description)
    {
        var existingRole = await roleManager.FindByNameAsync(name);
        if (existingRole is not null)
        {
            existingRole.Description = description;
            existingRole.IsSystem = true;
            existingRole.UpdatedAt = DateTimeOffset.UtcNow;
            var updateResult = await roleManager.UpdateAsync(existingRole);
            ThrowIfIdentityFailed(updateResult, $"update role '{name}'");
            return existingRole;
        }

        var role = new ApplicationRole
        {
            Name = name,
            Description = description,
            IsSystem = true
        };

        var result = await roleManager.CreateAsync(role);
        ThrowIfIdentityFailed(result, $"create role '{name}'");

        return role;
    }

    private static async Task<Permission> EnsurePermissionAsync(
        AppDbContext dbContext,
        string code,
        string name,
        string module,
        string resource,
        string action,
        string description)
    {
        var permission = await dbContext.Permissions
            .FirstOrDefaultAsync(item => item.Code == code);

        if (permission is null)
        {
            permission = new Permission
            {
                Code = code,
                CreatedAt = DateTimeOffset.UtcNow
            };
            dbContext.Permissions.Add(permission);
        }

        permission.Name = name;
        permission.Module = module;
        permission.Resource = resource;
        permission.Action = action;
        permission.Type = "api";
        permission.Description = description;
        permission.IsEnabled = true;
        permission.UpdatedAt = DateTimeOffset.UtcNow;

        return permission;
    }

    private static async Task EnsureRolePermissionAsync(
        AppDbContext dbContext,
        ApplicationRole role,
        Permission permission)
    {
        var exists = await dbContext.RolePermissions.AnyAsync(rolePermission =>
            rolePermission.RoleId == role.Id &&
            rolePermission.PermissionId == permission.Id);

        if (exists)
        {
            return;
        }

        dbContext.RolePermissions.Add(new RolePermission
        {
            RoleId = role.Id,
            PermissionId = permission.Id
        });
    }

    private static void ThrowIfIdentityFailed(IdentityResult result, string action)
    {
        if (result.Succeeded)
        {
            return;
        }

        throw new InvalidOperationException(
            $"Failed to {action}: {string.Join("; ", result.Errors.Select(error => error.Description))}");
    }

    private static async Task EnsureUserAsync(
        UserManager<ApplicationUser> userManager,
        string email,
        string password,
        string displayName,
        string role)
    {
        var user = await userManager.FindByEmailAsync(email);
        if (user is null)
        {
            user = new ApplicationUser
            {
                UserName = email,
                Email = email,
                EmailConfirmed = true,
                DisplayName = displayName,
                CurrentLevel = "beginner",
                LearningGoal = "daily",
                MembershipStatus = "Free"
            };

            await userManager.CreateAsync(user, password);
        }

        if (!await userManager.IsInRoleAsync(user, role))
        {
            await userManager.AddToRoleAsync(user, role);
        }
    }

    private static Word Word(
        string lemma,
        string phonetic,
        string partOfSpeech,
        string meaningCn)
    {
        return new Word
        {
            Lemma = lemma,
            Phonetic = phonetic,
            PartOfSpeech = partOfSpeech,
            MeaningCn = meaningCn,
            CefrLevel = "A2"
        };
    }

    private static void AddSentence(
        AppDbContext dbContext,
        Scene scene,
        string level,
        string text,
        string translation,
        params (Word Word, string SurfaceText, int Priority)[] keywords)
    {
        var sentence = new Sentence
        {
            Scene = scene,
            Text = text,
            Translation = translation,
            Level = level,
            // Local setup generates TTS assets instead of pointing at demo objects that may not exist.
            AudioUrl = null,
            Source = "seed",
            Status = "published"
        };

        foreach (var keyword in keywords)
        {
            var startIndex = text.IndexOf(keyword.SurfaceText, StringComparison.OrdinalIgnoreCase);
            if (startIndex < 0)
            {
                continue;
            }

            sentence.Keywords.Add(new SentenceKeyword
            {
                Sentence = sentence,
                Word = keyword.Word,
                SurfaceText = keyword.SurfaceText,
                StartIndex = startIndex,
                EndIndex = startIndex + keyword.SurfaceText.Length,
                Priority = keyword.Priority
            });
        }

        dbContext.Sentences.Add(sentence);
    }
}
