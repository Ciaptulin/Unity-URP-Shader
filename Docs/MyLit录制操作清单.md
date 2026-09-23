# MyLit 录制操作清单

> Recorder 4.0.3 已装好。配合 MyLit Showcase Window 出片。

---

## 一、Recorder 一次性配置

1. `Window > General > Recorder > Recorder Window`
2. 左侧 **+ Add Recorder** → 选 **Movie**
3. 配置 Movie：
   - **Source**：`Game View`（关键，别选 Main Camera）
   - **Output Resolution**：`1920x1080`
   - **Frame Rate**：`30`（或 60）
   - **Cap FPS**：勾上
   - **Output File**：`Assets/Showcase/xxx.mp4`
   - **Encoder**：H.264 / MP4
4. **Game View 分辨率**：先切到 16:9 或 1920x1080（Recorder 以 Game View 为准）

---

## 二、录前准备（每次都要）

1. 场景：HDRI 天空盒 + 主光 + rim 光已就位
2. 相机：摆好构图，确认 Game 视图里画面满意
3. Showcase 窗口：拖好 Orbit Target（女主角）+ Camera Transform（Main Camera）
4. **先只开转台，不开参数扫描**，Start 空跑一遍确认构图 OK，Stop 还原

---

## 三、逐个特性的录制配置

> 每次录制流程：摆好相机 → 配好 Showcase → 点 Recorder 的 **START RECORDING** → 点 Showcase 的 **Start** → 录 15-25 秒 → 点 Showcase 的 **Stop** → 点 Recorder 的 **STOP RECORDING**

### ① 转台 + 金属度扫描（主打）
- **转台**：✅ 开，速度 15-20 度/秒
- **参数扫描**：Param Target = 金属球，Property = `_Metalness`，Min 0，Max 1，Cycle 6
- **时长**：20 秒（转大半圈 + 金属度来回 3 次）

### ② 点阵镂空特写（主打）
- **转台**：❌ 关（相机拉近固定）
- **参数扫描**：Param Target = 镂空球，Property = `_DotDensity`，Min 5，Max 30，Cycle 5
- **相机**：靠近球，占满画面
- **时长**：15 秒

### ③ 法线 + 视差（主打）
- **转台**：✅ 开，速度 10 度/秒（慢转看凹凸）
- **参数扫描**：Param Target = 红砖方块，Property = `_ParallaxStrength`，Min 0，Max 0.03，Cycle 8
- **相机**：侧视 30-45 度角，能看出视差
- **时长**：20 秒

### ④ 清漆 Clear Coat
- **转台**：✅ 开，速度 15 度/秒
- **参数扫描**：Param Target = 金属球，Property = `_ClearCoatStrength`，Min 0，Max 1，Cycle 6
- **时长**：20 秒

### ⑤ 自发光 + GI
- **转台**：❌ 关
- **参数扫描**：扫描 `_EmissionTint` 是 Color，**float 扫描不支持**，改为手动调
- **做法**：录一段固定机位，后期在 Inspector 里手动拖 HDR 强度（或者干脆只放静帧）
- **时长**：10 秒静帧

### ⑥ 遮挡贴图 AO
- **转台**：❌ 关
- **参数扫描**：Param Target = 红砖方块，Property = `_OcclusionStrength`，Min 0，Max 1，Cycle 5
- **时长**：15 秒

---

## 四、出片后处理

1. 视频在 `Assets/Showcase/`，从 Unity 项目里复制到别处
2. **不要提交大视频到 Git**，放 GitHub 用图床或 Release，B站直接上传
3. GitHub README 里放 **GIF**（用 ScreenToGif / ffmpeg 转），控制在 5MB 内

```bash
# ffmpeg 转 GIF 示例（如果装了 ffmpeg）
ffmpeg -i input.mp4 -vf "fps=15,scale=640:-1" -loop 0 output.gif
```

---

## 五、验收标准

- [ ] 每个特性都能一眼看出参数在变
- [ ] 起转不跳变、Stop 能还原
- [ ] 画面里没有 AI Navigation / Console 等杂物
- [ ] 至少 4 条主视频（金属 / 点阵 / 视差 / 清漆）

---

## 六、常见坑

| 现象 | 原因 | 解决 |
|------|------|------|
| 录出来黑屏 | Source 选了 Main Camera | 改 Game View |
| 视频没声音不影响 | Movie 源默认无音频 | 无所谓，本来就静音 |
| 帧率卡顿 | Game 视图太慢 | 降分辨率到 1280x720 重录 |
| 参数没变 | 属性名拼错 / 材质不是 MyLit | Console 看 HasProperty 是否命中 |
| Stop 后相机没还原 | 录制中改了引用 | 别在录制中动窗口字段 |
