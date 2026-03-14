---
name: xrs
description: 将小说转换成中国传统连环画风格的分镜脚本和图片生成提示词
---

# 连环画分镜脚本生成系统 (Enhanced Orchestrator)

将短篇/中篇小说转换为中国传统连环画分镜脚本，支持：
- **长篇分段处理** - 自动分割>8000字小说
- **并行帧生成** - 批量同时生成多帧
- **质量验证** - 独立Agent检查输出
- **增量重试** - 问题帧单独重新生成

---

## 架构概览

```
Orchestrator
    │
    ├─→ [1] Chunker (长篇分段)
    │
    ├─→ [2] Analyzer Agent (分析)
    │
    ├─→ [3] Batch Generators (并行生成)
    │       ├── Batch 1: 帧1-4
    │       ├── Batch 2: 帧5-8
    │       └── Batch 3: 帧9-12...
    │
    ├─→ [4] Validator Agent (验证)
    │
    ├─→ [5] Retry Loop (重试问题帧)
    │
    └─→ [6] Output (聚合输出)
```

---

## Step 1: 输入验证与长篇分段

### 1.1 预检查

```python
word_count = len(novel_text)

IF word_count > 16000:
    WARN("小说过长，建议精简或分册处理")
    
IF word_count > 8000:
    # 启用分段模式
    segments = chunk_novel(novel_text, max_size=8000)
ELSE:
    segments = [novel_text]
```

### 1.2 分段算法 (Chunking)

```python
def chunk_novel(text, max_size=8000):
    """
    按场景切换点分割长篇小说
    优先在以下位置切割：
    1. 章节标题 (# / ## / ***)
    2. 场景分隔符 (空行 + 时间/地点变化)
    3. 段落边界
    """
    chunks = []
    current_chunk = ""
    
    for paragraph in text.split("\n\n"):
        if len(current_chunk) + len(paragraph) > max_size:
            # 寻找最佳切割点
            if is_scene_break(paragraph):
                chunks.append(current_chunk)
                current_chunk = paragraph
            else:
                # 强制切割，但保留上下文重叠
                overlap = get_last_200_chars(current_chunk)
                chunks.append(current_chunk)
                current_chunk = overlap + "\n\n" + paragraph
        else:
            current_chunk += "\n\n" + paragraph
    
    if current_chunk:
        chunks.append(current_chunk)
    
    return chunks
```

### 1.3 分段元数据

对每个segment记录：
```json
{
  "segment_index": 1,
  "total_segments": 3,
  "char_start": 0,
  "char_end": 7800,
  "is_continuation": false,
  "shared_characters": []  // 跨段共享的角色
}
```

---

## Step 2: 调用 Analyzer Agent

对每个 segment 调用分析：

```
Task(
  description="分析小说段落 {segment_index}/{total_segments}",
  subagent_type="general",
  prompt=read_file("prompts/analyzer.md").replace("{{NOVEL_TEXT}}", segment)
)
```

**角色合并**：如果有多个segment，合并所有角色卡，确保一致性：

```python
merged_characters = {}
for result in analyzer_results:
    for name, desc in result["characters"].items():
        if name not in merged_characters:
            merged_characters[name] = desc
        else:
            # 保留更详细的描述
            if len(desc) > len(merged_characters[name]):
                merged_characters[name] = desc
```

---

## Step 3: 并行帧生成 (Batch Generators)

### 3.1 批量划分策略

```python
def create_batches(frame_plan, batch_size=4):
    """
    将帧分成多个批次，每批4帧
    """
    batches = []
    for i in range(0, len(frame_plan), batch_size):
        batch = {
            "batch_index": i // batch_size + 1,
            "frames": frame_plan[i:i+batch_size],
            "frame_numbers": list(range(i+1, min(i+batch_size+1, len(frame_plan)+1)))
        }
        batches.append(batch)
    return batches
```

### 3.2 并行调用

**关键**：使用多个 Task 同时调用，实现并行：

```
# 在同一个消息中发送多个 Task 调用
Task(
  description="生成帧1-4",
  subagent_type="general",
  prompt=batch_generator_prompt.format(batch=batches[0])
)

Task(
  description="生成帧5-8",
  subagent_type="general",
  prompt=batch_generator_prompt.format(batch=batches[1])
)

Task(
  description="生成帧9-12",
  subagent_type="general",
  prompt=batch_generator_prompt.format(batch=batches[2])
)
# ... 同时发送，并行执行
```

### 3.3 Batch Generator Prompt

见 `prompts/batch_generator.md`

---

## Step 4: Validator Agent

### 4.1 验证调用

```
Task(
  description="验证生成结果",
  subagent_type="general",
  prompt=read_file("prompts/validator.md").replace("{{FRAMES_JSON}}", all_frames)
)
```

### 4.2 验证规则

| 检查项 | 约束 | 错误级别 |
|-------|------|---------|
| 帧数 | 8-16帧 | ERROR |
| 旁白字数 | 50-100字/帧 | WARNING |
| 对话字数 | ≤30字/气泡 | WARNING |
| 角色一致性 | 外观描述完全匹配角色卡 | ERROR |
| 镜头多样性 | 至少3种不同镜头 | WARNING |
| 提示词结构 | 必须包含6个部分 | ERROR |
| 风格标签 | 含「中国传统连环画」「黑白线描」 | ERROR |
| JSON有效性 | 可解析 | ERROR |

### 4.3 验证输出格式

```json
{
  "is_valid": false,
  "error_count": 2,
  "warning_count": 3,
  "issues": [
    {
      "frame_number": 5,
      "field": "narration",
      "level": "WARNING",
      "message": "旁白字数102字，超过100字上限",
      "suggestion": "精简旁白，删除次要细节"
    },
    {
      "frame_number": 8,
      "field": "characters[0].appearance",
      "level": "ERROR",
      "message": "角色外观描述与角色卡不一致",
      "expected": "六旬退休老者，身形微胖...",
      "actual": "老年男子，穿着便装..."
    }
  ],
  "frames_to_retry": [5, 8]
}
```

---

## Step 5: 增量重试 (Retry Loop)

### 5.1 重试逻辑

```python
MAX_RETRIES = 3
retry_count = 0

while validation_result["frames_to_retry"] and retry_count < MAX_RETRIES:
    retry_count += 1
    
    # 只重新生成问题帧
    frames_to_fix = validation_result["frames_to_retry"]
    
    Task(
      description=f"重新生成问题帧 {frames_to_fix}",
      subagent_type="general",
      prompt=retry_generator_prompt.format(
        frames=frames_to_fix,
        issues=validation_result["issues"],
        characters=merged_characters
      )
    )
    
    # 替换原有帧
    for new_frame in retry_result["frames"]:
        all_frames[new_frame["frame_number"] - 1] = new_frame
    
    # 重新验证
    validation_result = validate(all_frames)

if validation_result["error_count"] > 0:
    WARN("仍有未解决的错误，请人工检查")
```

### 5.2 Retry Generator Prompt

见 `prompts/retry_generator.md`

---

## Step 6: 聚合输出

### 6.1 合并多段结果

```python
final_output = {
    "metadata": {
        "title": title,
        "author": author,
        "total_frames": sum(len(r["frames"]) for r in all_results),
        "segments": len(segments) if len(segments) > 1 else None,
        "style": "中国传统连环画（黑白线描）"
    },
    "characters": merged_characters,
    "frames": []  # 按顺序合并所有帧
}

frame_number = 1
for segment_result in all_results:
    for frame in segment_result["frames"]:
        frame["frame_number"] = frame_number  # 重新编号
        final_output["frames"].append(frame)
        frame_number += 1
```

### 6.2 输出文件

```
{标题}_连环画脚本.md
{标题}_连环画脚本.json
```

---

## 快速参考

### 批量大小建议

| 总帧数 | 批量大小 | 批次数 |
|-------|---------|--------|
| 8-12帧 | 4帧/批 | 2-3批 |
| 13-16帧 | 4帧/批 | 4批 |
| 17-24帧 | 6帧/批 | 3-4批 |

### 分段阈值

| 字数 | 处理方式 |
|-----|---------|
| ≤8000 | 单段处理 |
| 8001-16000 | 2段 |
| 16001-24000 | 3段 |
| >24000 | 警告用户分册 |

### 重试策略

| 错误类型 | 重试方式 |
|---------|---------|
| 旁白过长/过短 | 只重新生成narration字段 |
| 角色不一致 | 重新生成整帧，强调角色卡 |
| 结构缺失 | 重新生成image_prompt |
| JSON错误 | 重新生成整批 |

---

## 错误处理

| 错误 | 处理 |
|-----|------|
| Analyzer返回非JSON | 重试1次，强调输出格式 |
| 批量生成超时 | 减小batch_size重试 |
| 验证持续失败 | 输出当前结果+警告 |
| 分段上下文丢失 | 增加overlap区域 |
