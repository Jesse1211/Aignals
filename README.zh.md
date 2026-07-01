[English](README.md) | 中文

# Aignals

**为你的 Vibe Coding 而生的三色信号灯。**

Aignals 是一款免费、开源的 macOS 菜单栏应用，它把你的 AI 编码助手的活动状态变成一盏简单的信号灯。当你用 Claude Code 做 Vibe Coding 时，你不想一直盯着终端 —— 让 Aignals 替你盯。每个 Claude Code 会话都有自己的一盏彩灯，由助手自身的生命周期 hook 写入一个轻量状态文件来驱动。菜单栏显示一个紧凑的计数，下拉面板则展示每个会话的细节。

- 🔴 **红色** —— 某个会话正在工作（请等待）
- 🟡 **黄色** —— 某个会话需要你点击授权（去点 Allow）
- 🟢 **绿色** —— 轮到你了（会话已完成 / 正在等你）
- ⚪️ **灰色** —— 会话已断开（进程已终止）

瞄一眼菜单栏，就知道你的哪个 Vibe Coding 会话需要你了。

## 安装

```bash
brew tap Jesse1211/aignals
brew install --cask aignals
```

或从[最新发布页](https://github.com/Jesse1211/Aignals/releases/latest)下载最新的 `.dmg`。首次启动时，右键 → 打开，以绕过 Gatekeeper（该构建为自签名）。

安装应用后，从菜单运行 **Install Claude Code Hooks…**（或接受首次启动的提示）来完成接线。

更新：

```bash
brew update
brew upgrade --cask aignals
```

## 菜单栏显示什么

菜单栏标签是各状态会话数量的紧凑计数 —— 例如 `🔴2 🟡1 🟢3`。计数为 `0` 的状态分组会被隐藏。

| 颜色 | 状态 | 含义 | 你该做什么 |
|-------|-------|---------------|--------------------|
| 🔴 红 | `working` | Claude 正在运行（生成中或正在执行工具） | 等待 |
| 🟡 黄 | `waiting_permission` | Claude 被授权提示卡住了 | 去点 **Allow** |
| 🟢 绿 | `waiting_input` | Claude 完成了本轮 / 会话刚开始 | 轮到你了 —— 输入下一条消息 |
| ⚪️ 灰 | `disconnected` | 会话进程未经干净的 `/exit` 就死掉了（终端被关闭 / 被杀） | 用完后用 ✕ 关掉它 |

## 下拉面板（点击菜单栏图标）

点击图标会打开一个面板，**每个会话一行**，排序规则为**置顶优先，然后最新在上**。每一行显示：

| 元素 | 含义 |
|---------|---------|
| **彩色圆点** | 该会话的当前状态（红/黄/绿/灰，如上表） |
| **名称** | 项目名 —— **点击可重命名**。自定义名称保存在 `~/.aignals/overrides.json`，并在 hook 更新后依然保留 |
| **副标题** | 该会话此刻正在做什么，例如 `Editing MenuContent.swift`、`Running npm test`、`Waiting for input` —— 后面跟着已用时间 |
| **已用时间** | 面板打开时**每秒实时跳动**（例如 `5s` → `6s` → `1m`） |
| **📌 置顶按钮** | 置顶一个会话，使其无论状态如何变化都保持在顶部；再点一次取消置顶 |
| **🔇 静音按钮** | 仅为该会话关闭声音提醒；再点一次取消静音 |
| **✕ 移除** | 仅在**灰色（已断开）**行显示 —— 移除已死会话及其保存的偏好 |

各行可以**拖拽重排**，顺序会被保留。会话列表下方有一个 **Settings** 按钮，展开后有两组 —— **General**（Install Claude Code Hooks、Install aignals-hook CLI、Open `~/.aignals/`、Launch at Login、Uninstall）和 **Customization**（主题、一张 **Sounds** 卡片、一张 **Feishu** 卡片）。点击下拉面板的 **Aignals** 标题（带 ⓘ 标记）会打开关于窗口。**Quit** 始终留在折叠之外。

## 主题

Aignals 内置 **4 套主题** —— Glass Light、Glass Dark、Terminal 和 Vibrant，可在 **Settings → Customization → Theme** 中切换。选择时会弹出实时预览，方便你把面板搭配你的桌面和心情。

## 声音提醒

当一个会话切换到需要你的状态时 —— 🟡（等待授权）或 🟢（等待输入）—— Aignals 会播放一段简短的 macOS 系统音，让你分辨出需要哪种关注。切换到 🔴（工作中）是静音的。

在 **Settings → Play sounds** 下，这两个状态各自有独立的声音选择器：可选任意 macOS 系统音（Ping、Glass、Funk、Tink、Pop、Hero、Submarine、Blow）或选 **None** 为该状态静音。选中某个声音会立即试听。默认 🟡 为 Ping、🟢 为 Glass。声音有节流（每个会话每几秒最多一次，且应用启动时绝不播放）。用某行的 🔇 按钮为单个会话静音，或用 **Play sounds** 开关关闭全部声音。

> 声音在真实的会话状态切换时触发，这需要安装 Claude Code hook。如果没装，声音选择器会显示一行提醒和一个安装快捷入口（不装 hook 也能试听声音）。

## Feishu 通知

Aignals 也可以在相同的 🟡/🟢 切换时向 **Feishu（飞书/Lark）** 推送一条消息，与声音相互独立。设置方法：

1. 在一个 Feishu 群里：**更多 (···) → 设置 → 群机器人 → 添加机器人 → 自定义机器人**。给它起个名字（例如 "Aignals"）并添加。
2. 复制生成的 **webhook URL**（`https://open.feishu.cn/open-apis/bot/v2/hook/…`；Lark 国际版用 `open.larksuite.com`）。
3. （可选）在机器人的**安全设置**下，选一种：
   - **签名校验** —— 把 **secret** 复制到 Aignals 的 *Secret* 字段（最安全）。
   - **自定义关键词** —— 设置一个关键词，并在 Aignals 的 *Keyword* 字段填入同一个词。提示：用 `Aignals`（每条消息都以它开头）。
4. 在 Aignals 中：**Settings → Feishu notifications** → 粘贴 webhook URL（如有用到则连同 secret/keyword）→ **Send test message** 确认。

发送为尽力而为；如果失败，Settings 会在开关下方显示一行原因。

## 每日一言（Daily Quote）

下拉面板包含一张 **Daily Quote** 卡片，为你的 Vibe Coding 会话添一点鼓励。它从 [API Ninjas](https://api-ninjas.com/) 拉取名言，可以选择**分类**、**刷新**换一条，以及**收藏**你喜欢的（收藏的名言保存在 `~/.aignals/quotes.json`）。在 Settings 中填入你自己的 API Ninjas key 即可使用。

## 工作计时（Work Stopwatch）

内置的 **Work Stopwatch** 让你可以**上班打卡 / 下班打卡**来记录专注工作时间。每段会话都会被加入**每日工作日志**，还有一个专门的 **Stat window** 汇总你记录的工时。数据保存在 `~/.aignals/worklog.json`。

## 工作原理

Claude Code 会在关键时刻触发生命周期 hook。每个 hook 运行随附的 `aignals-hook` shell 脚本，它会原子地在 `~/.aignals/sessions/<session_id>.json` 下按会话写入/更新/删除一个 JSON 文件。Aignals 用 FSEvents 监听该目录并渲染信号灯。这个文件**就是**协议 —— 任何能写出符合格式的 JSON 文件的工具都能驱动这个指示器，不只是 Claude Code。

hook 事件到状态的映射如下：

| Hook 事件 | `aignals-hook` 子命令 | 产生的状态 |
|------------|---------------------------|-----------------|
| SessionStart | `on-sessionstart` | 🟢 `waiting_input`（创建文件） |
| UserPromptSubmit | `on-prompt` | 🔴 `working` |
| PreToolUse | `on-pretool` | 🔴 `working`（+ 当前动作） |
| Notification (permission_prompt) | `on-permission` | 🟡 `waiting_permission` |
| PostToolUse | `on-posttool` | 🔴 `working`（点 Allow 之后） |
| PermissionDenied | `on-permission-denied` | 🔴 `working`（点 Deny 之后） |
| Stop / Notification (idle_prompt) | `on-stop` / `on-idle` | 🟢 `waiting_input` |
| SessionEnd | `on-sessionend` | 删除文件（灯消失） |

一个进程**未经**干净 `/exit` 就死掉的会话不会触发任何 hook；Aignals 的后台存活检查（`PIDSweeper`）会检测到已死的 PID，并把那盏灯变成**灰色**而不是移除它。

## 手动测试

你不需要一个真实的 Claude Code 会话就能测试 UI —— 你可以自己驱动状态文件，方式与 Claude Code 相同（在 stdin 上传入一个 JSON payload）。每次写入都需要一个 `session_id` 和一个 `updated_at` 时间戳，且该时间戳必须**单调地新于**该会话上一次的写入（陈旧写入会被丢弃，这是设计如此）。

给脚本设一个快捷变量：

```bash
HOOK="$(brew --prefix)/Caskroom/aignals/*/Aignals.app/Contents/Resources/aignals-hook"
# (or, from a source checkout:)
HOOK=/path/to/Aignals/CLI/aignals-hook/aignals-hook
```

驱动一个会话走完它的完整生命周期（在每一步观察菜单栏圆点的变化）：

```bash
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# 🟢 create a session (green, waiting for input)
echo '{"session_id":"demo","cwd":"/tmp/demo","updated_at":"'$(ts)'"}' | "$HOOK" on-sessionstart

# 🔴 it starts working
echo '{"session_id":"demo","updated_at":"'$(ts)'"}' | "$HOOK" on-prompt

# 🔴 working on a specific file (shows "Editing main.swift" in the dropdown)
echo '{"session_id":"demo","tool_name":"Edit","tool_input":{"file_path":"main.swift"},"updated_at":"'$(ts)'"}' | "$HOOK" on-pretool

# 🟡 blocked on a permission prompt
echo '{"session_id":"demo","updated_at":"'$(ts)'"}' | "$HOOK" on-permission

# 🔴 you clicked Allow, it continues
echo '{"session_id":"demo","updated_at":"'$(ts)'"}' | "$HOOK" on-posttool

# 🟢 finished — your turn again
echo '{"session_id":"demo","updated_at":"'$(ts)'"}' | "$HOOK" on-stop

# remove the session (light disappears)
echo '{"session_id":"demo"}' | "$HOOK" on-sessionend
```

说明：

- **`on-sessionstart` 会创建**一个会话。更新类子命令（`on-prompt`、`on-pretool`、`on-permission`、`on-stop` 等）在会话文件尚不存在时也会**创建**它 —— 这就是 Aignals 如何接管一个在 hook 安装之前就已在运行的会话（它会在下一次活动时出现）。只有 `on-sessionend` 在文件缺失时会空操作。
- 用一个**不同的 `session_id`** 来添加另一盏灯。开几个就能看到菜单栏计数，例如 `🔴1 🟡1 🟢2`。
- 查看或清空当前会话：

  ```bash
  for f in ~/.aignals/sessions/*.json; do jq -r '"\(.session_id): \(.state)"' "$f"; done   # list
  find ~/.aignals/sessions -name '*.json' -delete                                          # clear all
  ```

- 下拉面板内的功能（重命名、拖拽重排、置顶、实时跳动）是面板里的鼠标交互 —— 打开下拉面板试试即可。

## 卸载

**最简单：** 打开菜单 → **Settings → Uninstall Aignals…**。它会移除 Aignals 的 Claude Code hook（保留你的其他 hook 不动）、`aignals-hook` CLI 链接，以及 `~/.aignals` 中的所有数据，然后请你把 `Aignals.app` 拖进废纸篓来收尾。对话框里有一个 **"Keep my saved data (work log & quotes)"** 复选框 —— 勾选后，它会保留 `~/.aignals/quotes.json`（以及 `worklog.json`）并移除其余一切。

如果想手动卸载 —— Aignals 把东西存在两个地方：`~/.claude/settings.json` 里的 hook 条目，以及它自己在 `~/.aignals/` 下的数据。要彻底移除：

1. **退出应用** —— 点击菜单栏图标 → **Quit Aignals**。

2. **从 `~/.claude/settings.json` 移除 hook。** 这只删除 Aignals 的 hook 条目，你的其他 hook 保持不变（需要 `jq`）：

   ```bash
   cp ~/.claude/settings.json ~/.claude/settings.json.bak   # backup first
   jq '
     .hooks |= with_entries(
       .value |= map(select(
         (.hooks // []) | any(.command? // "" | test("aignals-hook")) | not
       ))
     )
     | .hooks |= with_entries(select(.value | length > 0))
   ' ~/.claude/settings.json > ~/.claude/settings.json.tmp \
     && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
   ```

3. **移除 CLI 符号链接**（如果你运行过 *Install aignals-hook CLI…*）：

   ```bash
   rm -f ~/.local/bin/aignals-hook
   ```

4. **移除 Aignals 的数据**（会话文件、`config.json`、`overrides.json` 自定义名称/顺序、`quotes.json` 收藏的名言）：

   ```bash
   rm -rf ~/.aignals
   ```

5. **移除应用：**

   ```bash
   brew uninstall --cask aignals          # if installed via Homebrew
   # or, if you dragged it in manually:
   rm -rf /Applications/Aignals.app
   ```

Homebrew cask 的 `zap` 段也覆盖了 `~/.aignals` 和偏好 plist，所以 `brew uninstall --zap --cask aignals` 一步就能完成第 4–5 步（第 2–3 步仍需手动做）。
