using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Api.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddWrongWordSourceTracking : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "LastMistakeAt",
                schema: "public",
                table: "user_word_states",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "LastMistakeSentenceId",
                schema: "public",
                table: "user_word_states",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_user_word_states_LastMistakeSentenceId",
                schema: "public",
                table: "user_word_states",
                column: "LastMistakeSentenceId");

            migrationBuilder.AddForeignKey(
                name: "FK_user_word_states_sentences_LastMistakeSentenceId",
                schema: "public",
                table: "user_word_states",
                column: "LastMistakeSentenceId",
                principalSchema: "public",
                principalTable: "sentences",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_user_word_states_sentences_LastMistakeSentenceId",
                schema: "public",
                table: "user_word_states");

            migrationBuilder.DropIndex(
                name: "IX_user_word_states_LastMistakeSentenceId",
                schema: "public",
                table: "user_word_states");

            migrationBuilder.DropColumn(
                name: "LastMistakeAt",
                schema: "public",
                table: "user_word_states");

            migrationBuilder.DropColumn(
                name: "LastMistakeSentenceId",
                schema: "public",
                table: "user_word_states");
        }
    }
}
