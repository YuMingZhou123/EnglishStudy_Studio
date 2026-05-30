param(
    [string]$ContentPath = "",
    [string]$ReviewPath = "",
    [string]$OutputPath = "",
    [string]$ApiBaseUrl = "http://localhost:5180",
    [string]$AdminEmail = "admin@example.com",
    [string]$AdminPassword = 'Admin123$',
    [switch]$SkipAudioLookup
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($ContentPath)) {
    $ContentPath = Join-Path $PSScriptRoot "..\content\mvp-sentence-pack.json"
}

if ([string]::IsNullOrWhiteSpace($ReviewPath)) {
    $ReviewPath = Join-Path $PSScriptRoot "..\content\mvp-content-review.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "..\content\mvp-content-review.html"
}

$ContentPath = [System.IO.Path]::GetFullPath($ContentPath)
$ReviewPath = [System.IO.Path]::GetFullPath($ReviewPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$ApiBaseUrl = $ApiBaseUrl.TrimEnd("/")

if (-not (Test-Path -LiteralPath $ContentPath)) {
    throw "Content file not found: $ContentPath"
}

function Get-WordCount([string]$text) {
    return [regex]::Matches($text, "[A-Za-z]+(?:'[A-Za-z]+)?").Count
}

function Get-ReviewValue($reviewRow, [string]$fieldName) {
    if ($null -eq $reviewRow) {
        return ""
    }

    $property = $reviewRow.PSObject.Properties[$fieldName]
    if ($null -eq $property) {
        return ""
    }

    return [string]$property.Value
}

function ConvertTo-JsonBody($value) {
    return $value | ConvertTo-Json -Depth 20 -Compress
}

function Normalize-SentenceText([string]$text) {
    return ([regex]::Replace(([string]$text).Trim().ToLowerInvariant(), "\s+", " "))
}

function Get-PublishedAudioMap {
    if ($SkipAudioLookup) {
        return [pscustomobject]@{
            status = "skipped"
            error = ""
            rows = @{}
        }
    }

    try {
        $auth = Invoke-RestMethod `
            -Method Post `
            -Uri "$ApiBaseUrl/api/auth/login" `
            -ContentType "application/json" `
            -TimeoutSec 10 `
            -Body (ConvertTo-JsonBody @{ email = $AdminEmail; password = $AdminPassword })

        $token = [string]$auth.accessToken
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw "Admin login did not return an access token."
        }

        $sentenceResponse = Invoke-RestMethod `
            -Method Get `
            -Uri "$ApiBaseUrl/api/admin/sentences?status=published" `
            -Headers @{ Authorization = "Bearer $token" } `
            -TimeoutSec 20

        $map = @{}
        foreach ($sentence in @($sentenceResponse)) {
            $key = Normalize-SentenceText $sentence.text
            if ([string]::IsNullOrWhiteSpace($key) -or $map.ContainsKey($key)) {
                continue
            }

            $map[$key] = [pscustomobject]@{
                audioUrl = [string]$sentence.audioUrl
                audioAssetId = [string]$sentence.audioAssetId
                status = if ([string]::IsNullOrWhiteSpace([string]$sentence.audioUrl)) { "missing_audio_url" } else { "ready" }
            }
        }

        return [pscustomobject]@{
            status = "ready"
            error = ""
            rows = $map
        }
    }
    catch {
        return [pscustomobject]@{
            status = "unavailable"
            error = $_.Exception.Message
            rows = @{}
        }
    }
}

$reviewRowsByNumber = @{}
if (Test-Path -LiteralPath $ReviewPath) {
    foreach ($row in @(Import-Csv -LiteralPath $ReviewPath -Encoding UTF8)) {
        $rowNumber = 0
        if ([int]::TryParse([string]$row.RowNumber, [ref]$rowNumber)) {
            $reviewRowsByNumber[$rowNumber] = $row
        }
    }
}

$json = Get-Content -LiteralPath $ContentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($json.items)
$audioMap = Get-PublishedAudioMap

$rows = for ($index = 0; $index -lt $items.Count; $index++) {
    $rowNumber = $index + 1
    $item = $items[$index]
    $reviewRow = $reviewRowsByNumber[$rowNumber]
    $audio = $audioMap.rows[(Normalize-SentenceText $item.text)]
    $audioUrl = if ($null -ne $audio) { [string]$audio.audioUrl } else { Get-ReviewValue $reviewRow "AudioUrl" }
    $audioAssetId = if ($null -ne $audio) { [string]$audio.audioAssetId } else { Get-ReviewValue $reviewRow "AudioAssetId" }
    $audioLookupStatus = if ($null -ne $audio) { [string]$audio.status } else { [string]$audioMap.status }
    $keywords = @($item.keywords) | ForEach-Object {
        "$($_.lemma) [$($_.surfaceText)] - $($_.meaningCn)"
    }

    [pscustomobject]@{
        RowNumber = $rowNumber
        SceneCode = $item.sceneCode
        SceneName = $item.sceneName
        Level = $item.level
        Text = $item.text
        Translation = $item.translation
        WordCount = Get-WordCount $item.text
        KeywordCount = @($item.keywords).Count
        Keywords = $keywords -join "; "
        AudioUrl = $audioUrl
        AudioAssetId = $audioAssetId
        AudioLookupStatus = $audioLookupStatus
        ReviewStatus = Get-ReviewValue $reviewRow "ReviewStatus"
        SentenceNotes = Get-ReviewValue $reviewRow "SentenceNotes"
        TranslationNotes = Get-ReviewValue $reviewRow "TranslationNotes"
        KeywordNotes = Get-ReviewValue $reviewRow "KeywordNotes"
        AudioNotes = Get-ReviewValue $reviewRow "AudioNotes"
        AudioReviewed = Get-ReviewValue $reviewRow "AudioReviewed"
        AudioReviewedAt = Get-ReviewValue $reviewRow "AudioReviewedAt"
        FinalNotes = Get-ReviewValue $reviewRow "FinalNotes"
    }
}

$rowsJson = ($rows | ConvertTo-Json -Depth 12).Replace("</script>", "<\/script>")

$html = @'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>EnglishStudy MVP Content Review</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f7f8fa;
      --panel: #ffffff;
      --ink: #17202a;
      --muted: #5f6b7a;
      --line: #d9dee7;
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
      width: min(1200px, calc(100% - 32px));
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
    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      padding: 0 0 14px;
    }
    select, button, textarea { font: inherit; }
    select, button {
      height: 36px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: white;
      color: var(--ink);
      padding: 0 10px;
    }
    button {
      cursor: pointer;
      font-weight: 600;
    }
    button.primary {
      border-color: var(--accent);
      background: var(--accent);
      color: white;
    }
    main { padding: 18px 0 32px; }
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
    .cards {
      display: grid;
      gap: 12px;
    }
    .card {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 14px;
    }
    .meta {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 10px;
    }
    .tag {
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 2px 8px;
      background: #f8fafc;
      color: #334155;
    }
    .sentence {
      margin: 0 0 8px;
      font-size: 18px;
      font-weight: 700;
    }
    .translation {
      margin: 0 0 10px;
      color: #334155;
    }
    .keywords {
      margin: 0 0 12px;
      color: var(--muted);
      font-size: 13px;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
      margin-bottom: 10px;
    }
    .audio-check {
      display: inline-flex;
      grid-template-columns: auto;
      gap: 6px;
      align-items: center;
      min-height: 36px;
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 0 10px;
      background: #f8fafc;
      color: #334155;
      font-size: 13px;
    }
    .notes {
      display: grid;
      grid-template-columns: repeat(5, minmax(0, 1fr));
      gap: 8px;
    }
    textarea {
      width: 100%;
      min-height: 72px;
      resize: vertical;
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 8px;
      color: var(--ink);
      background: #fff;
    }
    label {
      display: grid;
      gap: 4px;
      color: var(--muted);
      font-size: 12px;
      font-weight: 600;
    }
    .gate-ok { color: var(--accent); }
    .gate-warn { color: var(--warn); }
    .gate-bad { color: var(--bad); }
    @media (max-width: 860px) {
      .top { align-items: flex-start; flex-direction: column; }
      .summary { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .notes { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <header>
    <div class="wrap">
      <div class="top">
        <div>
          <h1>MVP Content Review Desk</h1>
          <p class="hint">Review sentence text, translation, keywords, and the actual published audio when available. Exported CSV works with summarize-content-review.ps1.</p>
        </div>
        <button class="primary" id="exportCsv">Export CSV</button>
      </div>
      <div class="toolbar">
        <select id="sceneFilter"></select>
        <select id="levelFilter"></select>
        <select id="batchFilter"></select>
        <select id="statusFilter">
          <option value="">All statuses</option>
          <option value="blank">Not reviewed</option>
          <option value="pass">pass</option>
          <option value="fix_sentence">fix_sentence</option>
          <option value="fix_translation">fix_translation</option>
          <option value="fix_keyword">fix_keyword</option>
          <option value="fix_audio">fix_audio</option>
          <option value="remove">remove</option>
        </select>
        <button id="markVisiblePass">Mark visible pass after review</button>
        <button id="clearVisibleStatus">Clear visible status</button>
        <button id="stopAudio">Stop audio</button>
      </div>
    </div>
  </header>
  <main class="wrap">
    <section class="summary" id="summary"></section>
    <section class="cards" id="cards"></section>
  </main>
  <script type="application/json" id="review-data">__REVIEW_ROWS_JSON__</script>
  <script>
    const rows = JSON.parse(document.getElementById("review-data").textContent);
    const fields = [
      "RowNumber", "SceneCode", "SceneName", "Level", "Text", "Translation",
      "KeywordCount", "Keywords", "AudioUrl", "AudioAssetId", "AudioLookupStatus", "AudioReviewed",
      "AudioReviewedAt", "ReviewStatus", "SentenceNotes", "TranslationNotes", "KeywordNotes", "AudioNotes", "FinalNotes"
    ];
    const statusOptions = ["", "pass", "fix_sentence", "fix_translation", "fix_keyword", "fix_audio", "remove"];
    const storageKey = `english-study-content-review:${location.pathname}`;
    const saved = JSON.parse(localStorage.getItem(storageKey) || "{}");

    function valueOf(row, field) {
      const rowState = saved[row.RowNumber] || {};
      return rowState[field] ?? row[field] ?? "";
    }

    function saveValue(rowNumber, field, value) {
      saved[rowNumber] ||= {};
      saved[rowNumber][field] = value;
      if (field === "AudioReviewed") {
        saved[rowNumber].AudioReviewedAt = isYes(value) ? new Date().toISOString() : "";
      }
      localStorage.setItem(storageKey, JSON.stringify(saved));
      renderSummary();
    }

    function isYes(value) {
      return ["yes", "y", "true", "1"].includes(String(value ?? "").trim().toLowerCase());
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

    const audioPlayer = new Audio();

    function markAudioReviewed(row) {
      saved[row.RowNumber] ||= {};
      saved[row.RowNumber].AudioReviewed = "yes";
      saved[row.RowNumber].AudioReviewedAt = new Date().toISOString();
      localStorage.setItem(storageKey, JSON.stringify(saved));
      renderCards();
      renderSummary();
    }

    function play(row, rate) {
      if (row.AudioUrl) {
        window.speechSynthesis?.cancel();
        audioPlayer.pause();
        audioPlayer.currentTime = 0;
        audioPlayer.src = row.AudioUrl;
        audioPlayer.playbackRate = rate;
        audioPlayer.play().then(() => {
          markAudioReviewed(row);
        }).catch(error => {
          alert(`Audio playback failed. Mark fix_audio if this happens during review.\n\n${error.message}`);
        });
        return;
      }

      if (!("speechSynthesis" in window)) {
        alert("No published audio URL is embedded for this row, and this browser does not support speechSynthesis.");
        return;
      }
      window.speechSynthesis.cancel();
      const utterance = new SpeechSynthesisUtterance(row.Text);
      utterance.lang = "en-US";
      utterance.rate = rate;
      window.speechSynthesis.speak(utterance);
      markAudioReviewed(row);
    }

    function renderFilters() {
      const scenes = [...new Set(rows.map(row => row.SceneCode))].sort();
      const levels = ["beginner", "intermediate", "advanced"];
      const batchSize = 20;
      const batchCount = Math.ceil(rows.length / batchSize);
      document.getElementById("sceneFilter").innerHTML = [
        `<option value="">All scenes</option>`,
        ...scenes.map(scene => `<option value="${escapeHtml(scene)}">${escapeHtml(scene)}</option>`)
      ].join("");
      document.getElementById("levelFilter").innerHTML = [
        `<option value="">All levels</option>`,
        ...levels.map(level => `<option value="${escapeHtml(level)}">${escapeHtml(level)}</option>`)
      ].join("");
      document.getElementById("batchFilter").innerHTML = [
        `<option value="">All batches</option>`,
        ...Array.from({ length: batchCount }, (_, index) => {
          const start = index * batchSize + 1;
          const end = Math.min((index + 1) * batchSize, rows.length);
          return `<option value="${start}-${end}">Rows ${start}-${end}</option>`;
        })
      ].join("");
    }

    function setFilterFromQuery(filterId, queryName) {
      const value = new URLSearchParams(location.search).get(queryName);
      if (!value) return;

      const filter = document.getElementById(filterId);
      const hasOption = Array.from(filter.options).some(option => option.value === value);
      if (hasOption) {
        filter.value = value;
      }
    }

    function applyQueryFilters() {
      setFilterFromQuery("sceneFilter", "scene");
      setFilterFromQuery("levelFilter", "level");
      setFilterFromQuery("batchFilter", "batch");
      setFilterFromQuery("statusFilter", "status");
    }

    function getFilteredRows() {
      const scene = document.getElementById("sceneFilter").value;
      const level = document.getElementById("levelFilter").value;
      const batch = document.getElementById("batchFilter").value;
      const status = document.getElementById("statusFilter").value;
      const [batchStart, batchEnd] = batch
        ? batch.split("-").map(value => Number(value))
        : [0, Number.MAX_SAFE_INTEGER];
      return rows.filter(row => {
        const rowStatus = valueOf(row, "ReviewStatus").trim();
        return (!scene || row.SceneCode === scene)
          && (!level || row.Level === level)
          && row.RowNumber >= batchStart
          && row.RowNumber <= batchEnd
          && (!status || (status === "blank" ? !rowStatus : rowStatus === status));
      });
    }

    function renderCards() {
      const filteredRows = getFilteredRows();
      document.getElementById("cards").innerHTML = filteredRows.map(row => {
        const status = valueOf(row, "ReviewStatus");
        const audioReviewed = isYes(valueOf(row, "AudioReviewed"));
        const options = statusOptions.map(option =>
          `<option value="${option}" ${option === status ? "selected" : ""}>${option || "not_reviewed"}</option>`
        ).join("");
        return `
          <article class="card">
            <div class="meta">
              <span class="tag">#${row.RowNumber}</span>
              <span class="tag">${escapeHtml(row.SceneCode)}</span>
              <span class="tag">${escapeHtml(row.Level)}</span>
              <span class="tag">${row.WordCount} words</span>
              <span class="tag">${row.KeywordCount} keywords</span>
              <span class="tag ${row.AudioUrl ? "gate-ok" : "gate-warn"}">${row.AudioUrl ? "audio ready" : "audio missing"}</span>
              <span class="tag ${audioReviewed ? "gate-ok" : "gate-warn"}">${audioReviewed ? "audio reviewed" : "audio not reviewed"}</span>
              ${row.AudioUrl ? `<a class="tag" href="${escapeHtml(row.AudioUrl)}" target="_blank" rel="noreferrer">audio file</a>` : ""}
            </div>
            <p class="sentence">${escapeHtml(row.Text)}</p>
            <p class="translation">${escapeHtml(row.Translation)}</p>
            <p class="keywords">${escapeHtml(row.Keywords)}</p>
            <div class="actions">
              <button type="button" data-play="${row.RowNumber}" data-rate="1">Play</button>
              <button type="button" data-play="${row.RowNumber}" data-rate="0.75">Slow</button>
              <select data-field="ReviewStatus" data-row="${row.RowNumber}">${options}</select>
              <label class="audio-check">
                <input type="checkbox" data-field="AudioReviewed" data-row="${row.RowNumber}" ${audioReviewed ? "checked" : ""}>
                Audio reviewed
              </label>
            </div>
            <div class="notes">
              ${["SentenceNotes", "TranslationNotes", "KeywordNotes", "AudioNotes", "FinalNotes"].map(field => `
                <label>${field}
                  <textarea data-field="${field}" data-row="${row.RowNumber}">${escapeHtml(valueOf(row, field))}</textarea>
                </label>
              `).join("")}
            </div>
          </article>
        `;
      }).join("");
    }

    function renderSummary() {
      const statuses = rows.map(row => valueOf(row, "ReviewStatus").trim());
      const pass = statuses.filter(status => status === "pass").length;
      const fix = statuses.filter(status => status.startsWith("fix_") || status === "remove").length;
      const blank = statuses.filter(status => !status).length;
      const audioReviewed = rows.filter(row => isYes(valueOf(row, "AudioReviewed"))).length;
      const scenePass = {};
      const levelPass = {};
      rows.forEach(row => {
        if (valueOf(row, "ReviewStatus").trim() === "pass") {
          scenePass[row.SceneCode] = (scenePass[row.SceneCode] || 0) + 1;
          levelPass[row.Level] = (levelPass[row.Level] || 0) + 1;
        }
      });
      const sceneGate = Object.values(scenePass).filter(count => count >= 15).length;
      const levelGate = ["beginner", "intermediate", "advanced"].filter(level => (levelPass[level] || 0) >= 15).length;
      const ready = pass >= 100 && audioReviewed >= pass && fix === 0 && blank === 0 && sceneGate >= 5 && levelGate === 3;
      const metrics = [
        ["Total rows", rows.length, ""],
        ["pass", pass, pass >= 100 ? "gate-ok" : "gate-warn"],
        ["Fix rows", fix, fix === 0 ? "gate-ok" : "gate-bad"],
        ["Blank rows", blank, blank === 0 ? "gate-ok" : "gate-warn"],
        ["Audio reviewed", audioReviewed, audioReviewed >= pass && pass > 0 ? "gate-ok" : "gate-warn"],
        ["Scene gate", `${sceneGate}/5`, sceneGate >= 5 ? "gate-ok" : "gate-warn"],
        ["Level gate", `${levelGate}/3`, levelGate === 3 ? "gate-ok" : "gate-warn"]
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
      link.download = "mvp-content-review.csv";
      link.click();
      URL.revokeObjectURL(link.href);
    }

    function handleFieldChange(element) {
      const rowNumber = Number(element.dataset.row);
      const row = rows.find(item => item.RowNumber === rowNumber);
      if (!row) return;

      const field = element.dataset.field;
      const value = element.type === "checkbox" ? (element.checked ? "yes" : "") : element.value;

      if (field === "ReviewStatus" && value === "pass" && !isYes(valueOf(row, "AudioReviewed"))) {
        alert("Cannot mark this row as pass yet.\n\nPlay the row or tick Audio reviewed first.");
        element.value = valueOf(row, "ReviewStatus");
        return;
      }

      saveValue(element.dataset.row, field, value);
      if (field === "AudioReviewed") {
        renderCards();
      }
    }

    function setVisibleStatus(status) {
      const filteredRows = getFilteredRows();
      if (filteredRows.length === 0) {
        alert("No visible rows match the current filters.");
        return;
      }

      const label = status || "blank";
      if (status === "pass") {
        const phrase = "I REVIEWED THE VISIBLE ROWS";
        const missingAudioReview = filteredRows.filter(row => !isYes(valueOf(row, "AudioReviewed"))).length;
        if (missingAudioReview > 0) {
          alert(`Cannot mark visible rows as pass yet.\n\nRows not marked audio reviewed: ${missingAudioReview}.\nPlay each row or tick Audio reviewed before using bulk pass.`);
          return;
        }

        const response = prompt(
          `You are about to mark ${filteredRows.length} visible row(s) as pass.\n\nOnly continue if sentence text, translation, keywords, and audio experience have all been checked.\n\nType "${phrase}" to confirm.`
        );
        if (response !== phrase) return;
      } else {
        const confirmed = confirm(`Set ReviewStatus=${label} for ${filteredRows.length} visible row(s)?`);
        if (!confirmed) return;
      }

      filteredRows.forEach(row => {
        saved[row.RowNumber] ||= {};
        saved[row.RowNumber].ReviewStatus = status;
      });
      localStorage.setItem(storageKey, JSON.stringify(saved));
      renderCards();
      renderSummary();
    }

    renderFilters();
    applyQueryFilters();
    renderCards();
    renderSummary();

    document.getElementById("sceneFilter").addEventListener("change", renderCards);
    document.getElementById("levelFilter").addEventListener("change", renderCards);
    document.getElementById("batchFilter").addEventListener("change", renderCards);
    document.getElementById("statusFilter").addEventListener("change", renderCards);
    document.getElementById("markVisiblePass").addEventListener("click", () => setVisibleStatus("pass"));
    document.getElementById("clearVisibleStatus").addEventListener("click", () => setVisibleStatus(""));
    document.getElementById("stopAudio").addEventListener("click", () => {
      audioPlayer.pause();
      audioPlayer.currentTime = 0;
      window.speechSynthesis?.cancel();
    });
    document.getElementById("exportCsv").addEventListener("click", exportCsv);
    document.getElementById("cards").addEventListener("click", event => {
      const button = event.target.closest("button[data-play]");
      if (!button) return;
      const row = rows.find(item => item.RowNumber === Number(button.dataset.play));
      if (row) play(row, Number(button.dataset.rate));
    });
    document.getElementById("cards").addEventListener("input", event => {
      const element = event.target.closest("[data-field][data-row]");
      if (!element) return;
      if (element.tagName === "SELECT" || element.type === "checkbox") return;
      handleFieldChange(element);
    });
    document.getElementById("cards").addEventListener("change", event => {
      const element = event.target.closest("[data-field][data-row]");
      if (!element) return;
      handleFieldChange(element);
    });
  </script>
</body>
</html>
'@

$html = $html.Replace("__REVIEW_ROWS_JSON__", $rowsJson)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value $html -Encoding UTF8

[pscustomobject]@{
    outputPath = $OutputPath
    rows = $rows.Count
    usedExistingReview = (Test-Path -LiteralPath $ReviewPath)
} | ConvertTo-Json -Depth 3
