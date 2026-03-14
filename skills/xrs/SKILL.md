---
name: xrs
description: 将中文或翻译小说、短篇故事、章节片段转换成中国传统连环画风格的分镜脚本、角色卡和图片生成提示词。用于把叙事文本拆成连贯画面、统一角色外观、批量生成 image prompt、验证结果质量，并对问题帧做增量重试；也适用于长篇分段处理和修复已有分镜脚本。
---

# 连环画分镜脚本系统

把用户提供的叙事文本转换成结构化 JSON 分镜，再按需渲染成 Markdown。

按需读取这些模板，不要一次性全读：

- `prompts/analyzer.md`：先抽角色卡和分帧方案
- `prompts/generator.md`：单次生成全部帧，适合短文本
- `prompts/batch_generator.md`：分批并行生成帧，适合长文本或高质量模式
- `prompts/validator.md`：检查帧数、字段、角色一致性和提示词结构
- `prompts/retry_generator.md`：只修复问题帧

## 核心规则

1. 默认使用简体中文输出，除非用户明确要求其他语言。
2. 用户工件写入任务工作目录，不要写回本 skill 目录。
3. 所有模板一律使用字面量占位符替换，例如 `template.replace("{{NOVEL_TEXT}}", novel_text)`。不要使用 `.format()`。
4. 一旦角色卡确定，后续每帧都必须逐字复用该角色的 `appearance`。
5. 默认目标是完整讲清故事，而不是机械压缩。未指定时，短篇通常输出 8-16 帧；更长文本可按 segment 拆分后累计更多帧。
6. 能并行就并行：分析长篇时按 segment 并行，生成阶段按 batch 并行，验证和重试串行。
7. 任一子步骤返回非 JSON 时，先重跑该子步骤一次，并再次强调“只输出 JSON”。

## 输出契约

标准 JSON 输出结构：

```json
{
  "metadata": {
    "title": "标题",
    "author": "作者或佚名",
    "style": "中国传统连环画（黑白线描）"
  },
  "characters": {
    "角色名": "完整外观描述"
  },
  "frames": [
    {
      "frame_number": 1,
      "plot_marker": "开场",
      "scene": {
        "time": "白天",
        "location": "地点",
        "atmosphere": "氛围"
      },
      "characters": [
        {
          "name": "角色名",
          "appearance": "与角色卡完全一致",
          "action": "该帧动作"
        }
      ],
      "shot_type": "全景",
      "narration": "50-100 字左右的旁白",
      "dialogue": [
        {
          "speaker": "角色名",
          "text": "单气泡不超过 30 字"
        }
      ],
      "image_prompt": "包含 [1-场景] 到 [6-风格] 的完整提示词"
    }
  ]
}
```

如用户要求写文件，默认输出：

- `{标题}_连环画脚本.json`
- `{标题}_连环画脚本.md`

## 选择工作模式

### 单次生成模式

满足以下任一条件时优先使用：

- 文本较短，约 `<= 3000` 汉字
- 用户只要一个快速初稿
- 目标帧数不超过 `8`

流程：

1. 先运行 `analyzer.md` 得到角色卡和 `frame_plan`
2. 再运行 `generator.md` 一次性生成全部帧
3. 用 `validator.md` 验证
4. 有问题时用 `retry_generator.md` 修复问题帧

### 编排模式

满足以下任一条件时使用：

- 文本较长，约 `> 3000` 汉字
- 用户明确要稳定质量
- 需要并行提速
- 需要长篇分段

流程：

1. 预处理和分段
2. `analyzer.md` 先产出角色卡和分帧方案
3. `batch_generator.md` 按 batch 并行生成
4. `validator.md` 统一验证
5. `retry_generator.md` 只修复失败帧
6. 聚合最终结果

## 1. 预处理与分段

### 文本预处理

- 规范换行和空白，保留段落边界。
- 用字符数而不是 token 粗估规模：`len(novel_text)`。
- 如果文本超过 `24000` 汉字，先提醒用户质量和耗时都会下降，建议按章节处理；若用户仍要求整篇处理，可以继续。

### 分段规则

- `<= 8000` 汉字：单段处理
- `8001-16000` 汉字：拆成 2 段
- `16001-24000` 汉字：拆成 3 段
- 优先在章节标题、明显场景切换、段落边界切开
- 每段保留约 `150-250` 汉字 overlap，避免上下文断裂

对每个 segment 记录：

```json
{
  "segment_index": 1,
  "total_segments": 3,
  "char_start": 0,
  "char_end": 7800,
  "is_continuation": false
}
```

## 2. 分析阶段

### 调用方式

对每个 segment 读取 `prompts/analyzer.md`，替换：

- `{{NOVEL_TEXT}}`
- `{{FRAME_COUNT_RULE}}`

`{{FRAME_COUNT_RULE}}` 的推荐写法：

- 单段短篇：`目标总帧数 8-16 帧。`
- 长篇 segment：`这是长篇中的一个 segment，请为本段规划 4-8 帧，并保证剧情完整衔接。`
- 用户指定帧数时：`用户指定总帧数为 12，请据此规划。`

### 角色卡合并

多个 segment 的角色卡合并时，按以下顺序处理：

1. 同名角色优先保留更完整、更具体的描述
2. 一旦最终角色卡确定，后续生成阶段不得再扩写或改写
3. 发现明显冲突时，以最早出现且最符合原文的描述为准，并在最终说明中提示用户

## 3. 生成阶段

### 单次生成模式

读取 `prompts/generator.md`，替换：

- `{{CHARACTERS_JSON}}`
- `{{FRAME_PLAN_JSON}}`
- `{{NOVEL_TEXT}}`

生成完成后直接进入验证。

### 编排模式

先把 `frame_plan` 按 `4` 帧一批切分；仅当总帧数明显更多时才把 batch_size 提到 `6`。

对每个 batch 构造：

```json
{
  "batch_index": 1,
  "total_batches": 3,
  "frame_start": 1,
  "frame_end": 4
}
```

再读取 `prompts/batch_generator.md`，替换：

- `{{CHARACTERS_JSON}}`
- `{{BATCH_INDEX}}`
- `{{TOTAL_BATCHES}}`
- `{{FRAME_START}}`
- `{{FRAME_END}}`
- `{{BATCH_FRAMES_JSON}}`
- `{{RELEVANT_TEXT}}`

### `RELEVANT_TEXT` 组装规则

- 以该 batch 第一帧的 `text_start` 和最后一帧的 `text_end` 为锚点
- 从原文截取对应区间
- 前后各补 1 个自然段作为缓冲
- 如果无法精确定位，就回退到该 batch 对应 segment 的完整文本

### 并行规则

- 为每个 batch 启动独立子代理并行生成
- 不要等一个 batch 完成后再启动下一个
- 所有 batch 结束后，按 `frame_number` 排序聚合

## 4. 验证阶段

读取 `prompts/validator.md`，替换：

- `{{CHARACTERS_JSON}}`
- `{{FRAMES_JSON}}`
- `{{FRAME_COUNT_RULE}}`

推荐把 `{{FRAME_COUNT_RULE}}` 替换成明确句子，例如：

- `本次结果应为 12 帧。`
- `这是单个 segment 的结果，应为 5 帧。`

验证时重点检查：

- 帧数是否符合当前任务要求
- `characters[].appearance` 是否与角色卡逐字一致
- `dialogue` 是否为对象数组，且每个对象都含 `speaker` 和 `text`
- `image_prompt` 是否含 `[1-场景]` 到 `[6-风格]`
- 是否包含 `中国传统连环画` 与 `黑白线描`

## 5. 增量重试

若验证返回 `frames_to_retry`，最多重试 `3` 轮。

每轮读取 `prompts/retry_generator.md`，替换：

- `{{CHARACTERS_JSON}}`
- `{{FRAMES_TO_FIX}}`
- `{{ISSUES_JSON}}`
- `{{ORIGINAL_FRAMES_JSON}}`

要求重试结果继续返回统一 schema：

```json
{
  "retry_count": 1,
  "frames": [
    {
      "frame_number": 8
    }
  ]
}
```

然后：

1. 仅用新帧覆盖对应 `frame_number`
2. 保留未出错帧
3. 重新运行验证

若 3 轮后仍有 `ERROR`，交付当前最佳结果并明确标注残留问题。

## 6. 聚合与交付

### 聚合规则

- 多个 segment 的帧合并后重新编号
- `metadata.style` 固定写成 `中国传统连环画（黑白线描）`
- 最终 `characters` 只保留合并后的角色卡

### Markdown 渲染

若用户要 `.md` 文件，按以下顺序渲染：

1. 标题与元数据
2. 角色卡
3. 每帧的小节
4. `narration`
5. `dialogue`
6. `image_prompt`

## 常见故障

| 问题 | 处理 |
|---|---|
| 分析返回非 JSON | 重跑分析一次，强调“只输出 JSON” |
| 生成批次遗漏字段 | 重跑对应 batch，不要整批回滚全部结果 |
| 角色外观漂移 | 以最终角色卡强制覆盖并重试问题帧 |
| 对话结构错误 | 统一改成 `[{\"speaker\": \"...\", \"text\": \"...\"}]` |
| 长篇上下文断裂 | 增加 overlap 或让 `RELEVANT_TEXT` 回退为完整 segment |

## 最小执行顺序

1. 读 `analyzer.md`
2. 决定单次生成还是编排模式
3. 读对应生成模板
4. 读 `validator.md`
5. 必要时再读 `retry_generator.md`
