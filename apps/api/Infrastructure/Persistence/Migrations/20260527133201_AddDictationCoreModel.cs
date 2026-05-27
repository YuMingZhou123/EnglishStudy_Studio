using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddDictationCoreModel : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "media_assets",
                schema: "public",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Bucket = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    ObjectKey = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: false),
                    Url = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: false),
                    ContentType = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    Size = table.Column<long>(type: "bigint", nullable: false),
                    Source = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_media_assets", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "scenes",
                schema: "public",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Code = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    Name = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    Description = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    IsEnabled = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_scenes", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "words",
                schema: "public",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Lemma = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    Phonetic = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    PartOfSpeech = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    MeaningCn = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: false),
                    CefrLevel = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true),
                    ExamTags = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    Collocations = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_words", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "sentences",
                schema: "public",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Text = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: false),
                    Translation = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: false),
                    Level = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    SceneId = table.Column<Guid>(type: "uuid", nullable: false),
                    AudioUrl = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: true),
                    SlowAudioUrl = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: true),
                    AudioAssetId = table.Column<Guid>(type: "uuid", nullable: true),
                    Source = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    CreatedBy = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_sentences", x => x.Id);
                    table.ForeignKey(
                        name: "FK_sentences_media_assets_AudioAssetId",
                        column: x => x.AudioAssetId,
                        principalSchema: "public",
                        principalTable: "media_assets",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_sentences_scenes_SceneId",
                        column: x => x.SceneId,
                        principalSchema: "public",
                        principalTable: "scenes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_word_states",
                schema: "public",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    WordId = table.Column<Guid>(type: "uuid", nullable: false),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    Source = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    MistakeCount = table.Column<int>(type: "integer", nullable: false),
                    CorrectStreak = table.Column<int>(type: "integer", nullable: false),
                    NextReviewAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LastReviewedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_word_states", x => x.Id);
                    table.ForeignKey(
                        name: "FK_user_word_states_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "public",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_user_word_states_words_WordId",
                        column: x => x.WordId,
                        principalSchema: "public",
                        principalTable: "words",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "dictation_attempts",
                schema: "public",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    SentenceId = table.Column<Guid>(type: "uuid", nullable: false),
                    Mode = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    UserAnswer = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: false),
                    NormalizedAnswer = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: false),
                    Score = table.Column<double>(type: "double precision", nullable: false),
                    IsCorrect = table.Column<bool>(type: "boolean", nullable: false),
                    DetailJson = table.Column<string>(type: "jsonb", nullable: true),
                    HintCount = table.Column<int>(type: "integer", nullable: false),
                    ReplayCount = table.Column<int>(type: "integer", nullable: false),
                    DurationMs = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_dictation_attempts", x => x.Id);
                    table.ForeignKey(
                        name: "FK_dictation_attempts_sentences_SentenceId",
                        column: x => x.SentenceId,
                        principalSchema: "public",
                        principalTable: "sentences",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_dictation_attempts_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "public",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "sentence_keywords",
                schema: "public",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    SentenceId = table.Column<Guid>(type: "uuid", nullable: false),
                    WordId = table.Column<Guid>(type: "uuid", nullable: false),
                    SurfaceText = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    StartIndex = table.Column<int>(type: "integer", nullable: false),
                    EndIndex = table.Column<int>(type: "integer", nullable: false),
                    BlankGroup = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    Priority = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_sentence_keywords", x => x.Id);
                    table.ForeignKey(
                        name: "FK_sentence_keywords_sentences_SentenceId",
                        column: x => x.SentenceId,
                        principalSchema: "public",
                        principalTable: "sentences",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_sentence_keywords_words_WordId",
                        column: x => x.WordId,
                        principalSchema: "public",
                        principalTable: "words",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_dictation_attempts_SentenceId",
                schema: "public",
                table: "dictation_attempts",
                column: "SentenceId");

            migrationBuilder.CreateIndex(
                name: "IX_dictation_attempts_UserId_CreatedAt",
                schema: "public",
                table: "dictation_attempts",
                columns: new[] { "UserId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_media_assets_Bucket_ObjectKey",
                schema: "public",
                table: "media_assets",
                columns: new[] { "Bucket", "ObjectKey" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_scenes_Code",
                schema: "public",
                table: "scenes",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_sentence_keywords_SentenceId",
                schema: "public",
                table: "sentence_keywords",
                column: "SentenceId");

            migrationBuilder.CreateIndex(
                name: "IX_sentence_keywords_WordId",
                schema: "public",
                table: "sentence_keywords",
                column: "WordId");

            migrationBuilder.CreateIndex(
                name: "IX_sentences_AudioAssetId",
                schema: "public",
                table: "sentences",
                column: "AudioAssetId");

            migrationBuilder.CreateIndex(
                name: "IX_sentences_Level_Status",
                schema: "public",
                table: "sentences",
                columns: new[] { "Level", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_sentences_SceneId",
                schema: "public",
                table: "sentences",
                column: "SceneId");

            migrationBuilder.CreateIndex(
                name: "IX_user_word_states_NextReviewAt",
                schema: "public",
                table: "user_word_states",
                column: "NextReviewAt");

            migrationBuilder.CreateIndex(
                name: "IX_user_word_states_UserId_WordId",
                schema: "public",
                table: "user_word_states",
                columns: new[] { "UserId", "WordId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_user_word_states_WordId",
                schema: "public",
                table: "user_word_states",
                column: "WordId");

            migrationBuilder.CreateIndex(
                name: "IX_words_Lemma",
                schema: "public",
                table: "words",
                column: "Lemma",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "dictation_attempts",
                schema: "public");

            migrationBuilder.DropTable(
                name: "sentence_keywords",
                schema: "public");

            migrationBuilder.DropTable(
                name: "user_word_states",
                schema: "public");

            migrationBuilder.DropTable(
                name: "sentences",
                schema: "public");

            migrationBuilder.DropTable(
                name: "words",
                schema: "public");

            migrationBuilder.DropTable(
                name: "media_assets",
                schema: "public");

            migrationBuilder.DropTable(
                name: "scenes",
                schema: "public");
        }
    }
}
