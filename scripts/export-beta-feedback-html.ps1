param(
    [string]$FeedbackPath = "",
    [string]$OutputPath = "",
    [int]$UserCount = 10
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($FeedbackPath)) {
    $FeedbackPath = Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.html"
}

if ($UserCount -lt 1) {
    throw "UserCount must be greater than 0."
}

$FeedbackPath = [System.IO.Path]::GetFullPath($FeedbackPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

function Get-FieldValue($row, [string]$fieldName) {
    if ($null -eq $row) {
        return ""
    }

    $property = $row.PSObject.Properties[$fieldName]
    if ($null -eq $property) {
        return ""
    }

    return [string]$property.Value
}

$fields = @(
    "UserId",
    "UserType",
    "EnglishLevel",
    "CompletedTest",
    "IndependentCompletion",
    "StuckStep",
    "UnderstandsDifficulty",
    "WillingNext",
    "PerceivedUseful",
    "AudioIssue",
    "PageIssue",
    "ContentIssue",
    "Priority",
    "Notes"
)

$sourceRows = @(
    if (Test-Path -LiteralPath $FeedbackPath) {
        Import-Csv -LiteralPath $FeedbackPath -Encoding UTF8
    }
)

if ($sourceRows.Count -eq 0) {
    $sourceRows = for ($index = 1; $index -le $UserCount; $index++) {
        [pscustomobject]@{ UserId = "U{0:D2}" -f $index }
    }
}

$rows = @(for ($index = 0; $index -lt $sourceRows.Count; $index++) {
    $sourceRow = $sourceRows[$index]
    $row = [ordered]@{}
    foreach ($field in $fields) {
        $row[$field] = Get-FieldValue $sourceRow $field
    }

    if ([string]::IsNullOrWhiteSpace($row["UserId"])) {
        $row["UserId"] = "U{0:D2}" -f ($index + 1)
    }

    [pscustomobject]$row
})

$rowsJson = ($rows | ConvertTo-Json -Depth 8).Replace("</script>", "<\/script>")
$fieldsJson = ($fields | ConvertTo-Json -Depth 3).Replace("</script>", "<\/script>")

$html = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>EnglishStudy Internal Beta Feedback</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f6f7f9;
      --panel: #ffffff;
      --ink: #17202a;
      --muted: #607080;
      --line: #d8dee8;
      --accent: #0f766e;
      --warn: #b45309;
      --bad: #b91c1c;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      background: var(--bg);
      color: var(--ink);
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.5;
    }

    header {
      position: sticky;
      top: 0;
      z-index: 10;
      border-bottom: 1px solid var(--line);
      background: rgba(255, 255, 255, 0.94);
      backdrop-filter: blur(10px);
    }

    .wrap {
      width: min(1180px, calc(100% - 32px));
      margin: 0 auto;
    }

    .top {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
      padding: 16px 0;
    }

    h1 {
      margin: 0;
      font-size: 22px;
      letter-spacing: 0;
    }

    .hint {
      margin: 4px 0 0;
      color: var(--muted);
      font-size: 13px;
    }

    button, select, input, textarea {
      font: inherit;
    }

    button, select, input {
      min-height: 36px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: white;
      color: var(--ink);
      padding: 0 10px;
    }

    button {
      cursor: pointer;
      font-weight: 700;
    }

    button.primary {
      border-color: var(--accent);
      background: var(--accent);
      color: white;
    }

    main {
      padding: 18px 0 32px;
    }

    .summary {
      display: grid;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      gap: 10px;
      margin-bottom: 16px;
    }

    .metric {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 12px;
    }

    .metric strong {
      display: block;
      font-size: 22px;
    }

    .metric span {
      color: var(--muted);
      font-size: 12px;
    }

    .grid {
      display: grid;
      gap: 12px;
    }

    .card {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 14px;
    }

    .row {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
      margin-bottom: 10px;
    }

    .wide {
      grid-column: span 2;
    }

    .full {
      grid-column: 1 / -1;
    }

    label {
      display: grid;
      gap: 4px;
      color: var(--muted);
      font-size: 12px;
      font-weight: 700;
    }

    textarea {
      width: 100%;
      min-height: 72px;
      resize: vertical;
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 8px;
      color: var(--ink);
      background: white;
    }

    .gate-ok { color: var(--accent); }
    .gate-warn { color: var(--warn); }
    .gate-bad { color: var(--bad); }

    @media (max-width: 900px) {
      .top { align-items: flex-start; flex-direction: column; }
      .summary { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .row { grid-template-columns: 1fr; }
      .wide { grid-column: auto; }
    }
  </style>
</head>
<body>
  <header>
    <div class="wrap">
      <div class="top">
        <div>
          <h1>Internal Beta Feedback Form</h1>
          <p class="hint">Fill one row per tester. Exported CSV works with summarize-beta-feedback.ps1.</p>
        </div>
        <button class="primary" id="exportCsv">Export CSV</button>
      </div>
    </div>
  </header>
  <main class="wrap">
    <section class="summary" id="summary"></section>
    <section class="grid" id="cards"></section>
  </main>
  <script type="application/json" id="feedback-fields">__FIELDS_JSON__</script>
  <script type="application/json" id="feedback-data">__FEEDBACK_ROWS_JSON__</script>
  <script>
    const fields = JSON.parse(document.getElementById("feedback-fields").textContent);
    const rows = JSON.parse(document.getElementById("feedback-data").textContent);
    const storageKey = `english-study-beta-feedback:${location.pathname}`;
    const saved = JSON.parse(localStorage.getItem(storageKey) || "{}");
    const options = {
      UserType: ["", "university_student", "workplace_newcomer", "general_learner"],
      EnglishLevel: ["", "beginner", "intermediate", "advanced", "uncertain"],
      CompletedTest: ["", "yes", "no"],
      IndependentCompletion: ["", "yes", "no"],
      UnderstandsDifficulty: ["", "yes", "partial", "no"],
      WillingNext: ["", "yes", "average", "no"],
      PerceivedUseful: ["", "yes", "partial", "no"],
      AudioIssue: ["", "none", "too_fast", "too_slow", "mechanical", "low_volume", "playback_failed"],
      Priority: ["", "P0", "P1", "P2"]
    };

    function valueOf(row, field) {
      const rowState = saved[row.UserId] || {};
      return rowState[field] ?? row[field] ?? "";
    }

    function saveValue(userId, field, value) {
      saved[userId] ||= {};
      saved[userId][field] = value;
      localStorage.setItem(storageKey, JSON.stringify(saved));
      renderSummary();
    }

    function escapeHtml(value) {
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
    }

    function csvEscape(value) {
      return `"${String(value ?? "").replaceAll('"', '""')}"`;
    }

    function isYes(value) {
      return String(value ?? "").trim().toLowerCase() === "yes";
    }

    function isPartialOrYes(value) {
      const normalized = String(value ?? "").trim().toLowerCase();
      return normalized === "yes" || normalized === "partial" || normalized === "partly" || normalized === "average";
    }

    function isFilled(row) {
      return ["CompletedTest", "IndependentCompletion", "Notes"].some(field => valueOf(row, field).trim());
    }

    function renderField(row, field) {
      const id = row.UserId;
      const current = valueOf(row, field);
      if (options[field]) {
        return `
          <label>${field}
            <select data-user="${escapeHtml(id)}" data-field="${field}">
              ${options[field].map(option => `<option value="${option}" ${option === current ? "selected" : ""}>${option || "blank"}</option>`).join("")}
            </select>
          </label>
        `;
      }

      if (["StuckStep", "PageIssue", "ContentIssue", "Notes"].includes(field)) {
        return `
          <label class="${field === "Notes" ? "full" : "wide"}">${field}
            <textarea data-user="${escapeHtml(id)}" data-field="${field}">${escapeHtml(current)}</textarea>
          </label>
        `;
      }

      return `
        <label>${field}
          <input data-user="${escapeHtml(id)}" data-field="${field}" value="${escapeHtml(current)}">
        </label>
      `;
    }

    function renderCards() {
      document.getElementById("cards").innerHTML = rows.map(row => `
        <article class="card">
          <div class="row">
            ${fields.map(field => renderField(row, field)).join("")}
          </div>
        </article>
      `).join("");
    }

    function renderSummary() {
      const filled = rows.filter(isFilled).length;
      const completed = rows.filter(row => isYes(valueOf(row, "CompletedTest"))).length;
      const independent = rows.filter(row => isYes(valueOf(row, "IndependentCompletion"))).length;
      const difficulty = rows.filter(row => isPartialOrYes(valueOf(row, "UnderstandsDifficulty"))).length;
      const willing = rows.filter(row => isYes(valueOf(row, "WillingNext"))).length;
      const p0 = rows.filter(row => String(valueOf(row, "Priority")).trim().toUpperCase() === "P0").length;
      const ready = completed >= 5 && independent >= 4 && difficulty >= 4 && willing >= 3 && p0 === 0;
      const metrics = [
        ["Filled rows", filled, filled >= 5 ? "gate-ok" : "gate-warn"],
        ["Completed", completed, completed >= 5 ? "gate-ok" : "gate-warn"],
        ["Independent", independent, independent >= 4 ? "gate-ok" : "gate-warn"],
        ["Difficulty", difficulty, difficulty >= 4 ? "gate-ok" : "gate-warn"],
        ["Willing next", willing, willing >= 3 ? "gate-ok" : "gate-warn"],
        ["P0 issues", p0, p0 === 0 ? "gate-ok" : "gate-bad"]
      ];

      document.getElementById("summary").innerHTML = metrics.map(([label, value, className]) => `
        <div class="metric ${className}">
          <strong>${value}</strong>
          <span>${label}</span>
        </div>
      `).join("") + `
        <div class="metric ${ready ? "gate-ok" : "gate-warn"}">
          <strong>${ready ? "Ready" : "Not ready"}</strong>
          <span>Minimum gate</span>
        </div>
      `;
    }

    function exportCsv() {
      const lines = [
        fields.map(csvEscape).join(","),
        ...rows.map(row => fields.map(field => csvEscape(valueOf(row, field))).join(","))
      ];
      const blob = new Blob(["\ufeff" + lines.join("\r\n")], { type: "text/csv;charset=utf-8" });
      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = "internal-beta-feedback.csv";
      link.click();
      URL.revokeObjectURL(link.href);
    }

    renderCards();
    renderSummary();

    document.getElementById("exportCsv").addEventListener("click", exportCsv);
    document.getElementById("cards").addEventListener("input", event => {
      const element = event.target.closest("[data-user][data-field]");
      if (!element) return;
      saveValue(element.dataset.user, element.dataset.field, element.value);
    });
    document.getElementById("cards").addEventListener("change", event => {
      const element = event.target.closest("[data-user][data-field]");
      if (!element) return;
      saveValue(element.dataset.user, element.dataset.field, element.value);
    });
  </script>
</body>
</html>
'@

$html = $html.Replace("__FIELDS_JSON__", $fieldsJson)
$html = $html.Replace("__FEEDBACK_ROWS_JSON__", $rowsJson)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value $html -Encoding UTF8

[pscustomobject]@{
    outputPath = $OutputPath
    rows = $rows.Count
    usedExistingFeedback = (Test-Path -LiteralPath $FeedbackPath)
} | ConvertTo-Json -Depth 3
