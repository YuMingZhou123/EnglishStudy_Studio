# MVP 内容质量审核规范

版本：v0.1
日期：2026-05-28
状态：第一版内容审核规范

## 1. 目标

第一版内容审核只关注一件事：用户能否通过自然、准确、难度合适的英语句子，在语境里记住目标词。

审核对象：

- `content/mvp-sentence-pack.json`
- 后台导入后的场景、句子、单词、关键词
- TTS 或浏览器语音播放体验

## 2. 导出审核表

可以先把内容包导出成 CSV：

```powershell
.\scripts\export-content-review-sheet.ps1
.\scripts\export-content-review-html.ps1
.\scripts\summarize-content-review.ps1
```

默认输出：

```text
content/mvp-content-review.csv
content/mvp-content-review.html
```

审核时可以直接在 CSV 中填写 `ReviewStatus` 和各类备注；也可以打开 HTML 审核台，逐条选择状态、填写备注，再导出新的 CSV。建议状态：

HTML 审核台支持按场景、难度、20 条一组的批次、审核状态过滤，建议每次只处理一个批次，避免 120 条内容一次性审核时漏行。

- `pass`
- `fix_sentence`
- `fix_translation`
- `fix_keyword`
- `fix_audio`
- `remove`

审核完成后再次运行：

```powershell
.\scripts\summarize-content-review.ps1
```

`passesMinimumGate` 为 `true` 时，说明内容审核结果达到第一版最低标准。

## 3. 句子审核标准

每条句子需要满足：

- 英文自然，不像机器硬拼。
- 句子长度适合听写，不要过长。
- 没有明显语法错误。
- 没有明显文化、政治、宗教、成人、暴力等敏感内容。
- 场景归类合理。
- 难度与句子长度、词汇难度基本一致。
- 目标词出现在原句中。
- 目标词是值得学习的词，不是无意义填空。

建议长度：

- 初级：5 到 10 个英文词。
- 中级：8 到 14 个英文词。
- 高级：10 到 18 个英文词。

## 4. 中文翻译审核标准

中文翻译需要满足：

- 意思准确。
- 读起来像正常中文。
- 不需要逐词硬翻。
- 不加入英文原句没有的信息。
- 关键语义不能漏掉。
- 数字、时间、地点、人物关系不能错。

## 5. 关键词审核标准

每个关键词需要满足：

- `surfaceText` 必须能在句子中找到。
- `lemma` 应尽量使用基础词形。
- 中文释义要贴合当前语境。
- 词性尽量准确。
- 优先级越高，越适合初级模式挖空。
- 中级模式的多个空不能让句子完全失去上下文。
- 高级模式不依赖关键词空，但关键词仍用于反馈和错词本。

优先级建议：

- 100：最核心、最值得用户记的词。
- 80 到 90：重要语境词。
- 60 到 70：辅助理解词。

## 6. 难度审核标准

初级：

- 句子短。
- 语法结构简单。
- 挖空词通常是名词、动词、形容词等核心词。
- 用户看上下文能推测答案。

中级：

- 句子可以稍长。
- 可以包含从句、时间状语、原因状语。
- 多个关键词挖空后仍保留足够语境。

高级：

- 适合整句听写。
- 句子不能太绕。
- 可以有自然连接词和更抽象表达。
- 不应靠生僻专有名词增加难度。

## 7. 音频审核标准

第一版允许两种音频来源：

- 后台生成并绑定的 TTS 音频。
- 浏览器 `speechSynthesis` fallback。

导入内容后，优先运行：

```powershell
.\scripts\generate-missing-audio.ps1
```

这样可以把已发布句子绑定到 MinIO 中的 TTS 音频，减少不同浏览器 fallback 造成的听感差异。

人工听音时检查：

- 原速可以听清。
- 慢速明显变慢但不失真。
- 发音基本准确。
- 音量正常。
- 播放按钮响应正常。
- 无明显卡顿、破音、空音频。

如果某条句子 TTS 质量差，先记录 `fix_audio`，后续可换 voice、调 speed 或上传人工音频。

## 8. 审核流程

1. 运行内容结构校验：

```powershell
.\scripts\validate-mvp-content.ps1
.\scripts\audit-mvp-content-quality.ps1
```

2. 导出审核表：

```powershell
.\scripts\export-content-review-sheet.ps1
.\scripts\export-content-review-html.ps1
```

3. 人工逐行审核句子、翻译、关键词；也可以打开 `content/mvp-content-review.html` 使用审核台并导出 CSV。
4. 标记需要修改的行。
5. 回到 `content/mvp-sentence-pack.json` 修正。
6. 再次运行结构校验。
7. 重新导入内容包：

```powershell
.\scripts\import-mvp-content.ps1
```

8. 抽样进入前端听写页，检查播放和答题反馈。

## 9. 第一版通过标准

内容可以进入内测的最低标准：

- 120 条内容全部通过结构校验。
- `.\scripts\audit-mvp-content-quality.ps1` 通过自动内容质量体检。
- 至少 100 条句子人工审核为 `pass`。
- 每个场景至少 15 条可用句子。
- 初级、中级、高级都至少有 15 条可用句子。
- 没有明显错误翻译。
- 没有关键词无法匹配原句的问题。
- 抽样 20 条音频播放无阻断问题。

## 10. 后续扩展

第一版验证通过后，再考虑：

- 扩到 300 条句子。
- 增加主题标签。
- 增加 CEFR 分级。
- 增加考试标签。
- 增加人工录音或更高质量 TTS。
- 引入 AI 辅助生成，但仍保留人工审核。
