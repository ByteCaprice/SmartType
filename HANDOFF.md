# SwiftType 工作交接

更新时间：2026-09-04（transparent-prediction 已实现并通过全部测试，尚未安装验证）

## 一、当前目标

1. 让 Microsoft Edge、企业微信等 Chromium/CEF 客户端在输入过程中也能用中/英（Caps Lock）键切换输入法，而不是只切换大小写。
2. 让系统输入源切换 HUD 显示新的 `S` 图标，而不是旧蓝色双箭头。

## 二、当前版本状态

- 安装位置：`~/Library/Input Methods/SwiftType.app`
- Bundle ID：`com.matthew.inputmethod.SwiftType`
- 已安装版本：`20260904085803`（不含本次 transparent-prediction 改动）
- 已确认运行进程的可执行文件来自上述安装目录，且启动时间晚于安装时间，不是残留旧进程。
- 安装包为 Universal `arm64 + x86_64`，签名验证通过。
- `CapsLockDelayOverride` 已恢复系统默认值 `75`。
- **本次工作区改动尚未构建安装**，需要重新运行 `scripts/install.sh`。

## 三、已确认根因（为什么 Edge/企业微信不切换）

用 45 秒实时日志采样（subsystem `com.matthew.inputmethod.SwiftType`，category `InputController`），用户在 Edge 中多次按中/英键，日志中完全没有 `Caps Lock event received`。结论：

- Caps Lock `flagsChanged` 事件在进入 InputMethodKit controller 之前就被 Chromium/CEF 截走。
- 问题不在 SwiftType 的 Caps Lock 回调或 composition 提交代码；继续修改 `handle(_:client:)` 的 Caps Lock 分支对这些应用无效。
- 真正的机制（来自 Chromium 源码 `render_widget_host_view_cocoa.mm`）：marked text 活跃时，AppKit/Chromium 会推迟输入源切换。SwiftType 之前的 inline 模式（`setMarkedText` 显示下划线 preedit）正是让切换被推迟的原因。
- Chromium 不尊重 IMK `handle()` 的布尔返回值：如果事件前后都没有 marked text，且输入法没有在同一 keyDown 中插入多字符文本，原始按键仍会被转发给网页（重复字母、重复 Backspace 的来源，见 squirrel#906、fcitx5-macos 的 dummy preedit workaround）。

本机应用信息：

- Microsoft Edge：`com.microsoft.edgemac`，Chromium 152。
- 企业微信：`com.tencent.WeWorkMac`，内嵌 CEF 138 + FlutterMacOS，helper 进程前缀 `88L2Q4487U.com.tencent.wework`。

## 四、解决方案架构

### 4.1 三种客户端模式（`Input/InputClientPolicy.swift`）

参照 hallelujahIM 的 `TerminalPassthrough`（独立、纯 Foundation、可单测的策略类），所有按键路由先经过 `InputClientPolicy.mode(forBundleIdentifier:)` 判定：

| 模式 | 行为 | 适用应用 |
|---|---|---|
| `.passthrough` | 所有按键原样返回 `false`，不启动 composition | 终端（Terminal、iTerm2、Ghostty、WezTerm、kitty、Alacritty、Warp、Hyper）、VS Code、SwiftType 自身窗口 |
| `.transparentPrediction` | 字母由应用自己写入，SwiftType 只维护镜像 buffer 提供候选，全程无 marked text | Chromium/CEF 家族（Edge、Chrome、Brave、Vivaldi、Opera、企业微信等） |
| `.inline` | 原有行为：`setMarkedText` 下划线 preedit + 候选 | 其余所有原生应用（TextEdit、Safari、Xcode 等） |

**判定优先级**（重要：passthrough 优先于 Chromium 启发式，所以 VS Code 的 Electron 身份不会把它拉进透明预测）：

1. bundle ID 为空 → `.inline`
2. 等于 SwiftType 自身 bundle ID → `.passthrough`
3. 命中 `passthroughBundleIdentifiers` → `.passthrough`
4. 命中透明预测（见下）→ `.transparentPrediction`
5. 其他 → `.inline`

**透明预测命中规则**（按顺序）：

1. UserDefaults 数组 `transparentPredictionBundleIdentifiers` 中的条目（精确匹配或前缀匹配）——**以后新应用坏掉，无需改代码**：
   ```bash
   defaults write com.matthew.inputmethod.SwiftType transparentPredictionBundleIdentifiers -array-add 'com.foo.bar'
   ```
2. 内置已知 ID：`com.microsoft.edgemac`、`com.tencent.WeWorkMac`、`com.google.Chrome`、`org.chromium.Chromium`、`com.brave.Browser`、`company.thebrowser.Browser`、`com.operasoftware.Opera`、`com.vivaldi.Vivaldi`
3. 内置前缀：`88L2Q4487U.com.tencent.wework`、`com.microsoft.edgemac`、`com.google.Chrome`、`com.brave.Browser`（覆盖 Canary/Dev/helper 变体）
4. 启发式：bundle ID 小写后包含 `chrome` / `chromium` / `edgemac` / `brave.browser` / `vivaldi` / `operasoftware.opera`

`InputController.terminalBundleIdentifiers` 现在只是 `InputClientPolicy.passthroughBundleIdentifiers` 的别名，旧调用点不变；`InputController.usesTransparentPrediction(bundleIdentifier:)` 是对 policy 的薄封装。

### 4.2 透明预测按键语义（`Input/Controller/InputControllerTransparentPrediction.swift`）

核心思想：**客户端拥有字面文本，SwiftType 只维护镜像**。每个 keyDown 顶部先做 stale 检查，任何时刻都不调用 `setMarkedText`（除了下述一次性 prime），所以系统没有 composition 可阻塞 Caps Lock 切换。

| 事件 | 行为 | 返回值 |
|---|---|---|
| 字母（含 Shift） | 首字母时记录 `compositionBaseline`（`selectedRange()`）和 `compositionClientBundleID`；追加到镜像 buffer，更新候选窗。**不写客户端** | `false`（客户端自己写入） |
| 撇号 `'`/`’`（buffer 非空） | 同字母，保持 "don't" 在一个 buffer | `false` |
| Backspace | 镜像 buffer 减一、`expectedCursor` 回退；buffer 空则整体丢弃。**不替客户端删除** | `false`（客户端自己删除，天然不会双删） |
| Space（候选窗可见、选中候选） | 插入 suffix（候选去掉已输入前缀）+ 空格，`NSNotFound` range | `true` |
| Space（候选窗可见、literal 选中） | 丢弃镜像（字母已在 field 里，空格由客户端自己打），置 `didAutoInsertTrailingSpace` | `false` |
| Space（无候选） | 透传 | `false` |
| Return | 同 Space，但无尾随空格；literal 时透传（表单提交不受影响） | `true` / `false` |
| 数字 1–7（候选窗可见） | 对应槽位选词：literal 槽 → `commitTransparentWord(buffer)`；预测槽 → `currentPredictions[predIdx]` 加大小写保留后提交；空槽位返回 `false`（数字透传，不吞键） | `true` / `false` |
| Escape / 方向键 / Tab | 丢弃镜像 buffer 和候选窗，透传（Chromium 会把"消费但不写"的键重投递，所以不消费） | `false` |
| Cmd/Ctrl/Option 组合 | 丢弃镜像，透传 | `false` |
| 多字符 `event.characters`（死键等） | 丢弃镜像，透传 | `false` |
| **Caps Lock `flagsChanged`**（在 `InputControllerKeyHandling.swift` 的 handle 入口） | **只丢弃镜像 buffer，不 insert、不 setMarkedText** —— 字母已在 field 里，无需 flush，切换即时且完全交给系统 | `false` |

**选词提交的三条路径**（`commitTransparentWord`）：

1. 候选是 buffer 的大/小写无关前缀且 suffix 长度 > 1：只 `insertText(suffix, NSNotFound)` —— Chromium 的 deferred/masked 路径，不会泄漏原始按键。
2. 纠正型候选（如 `teh`→`the`，suffix ≤ 1 或非前缀）：先 `verifiedTypedRegion`（用 `attributedSubstring` 验证 baseline 起始的已输入区域与 buffer 大小写无关一致），一致则 `primeAndCommit` —— 在**同一个 keyDown 内**先 `setMarkedText` 覆盖已输入区域再 `insertText`。marked 阶段只存在于这一次同步事件中，事件结束后无 composition，不影响 Caps Lock（对齐 Squirrel 的 `force_marked_text_for_direct_commit`）。
3. 验证失败或 `selectedRange` 为 `NSNotFound`：退化为仅插入 suffix，或放弃提交（绝不在未验证位置覆盖文本）。

**Stale 检测**（每次 keyDown 顶部、buffer 非空时）：bundle ID 变化、selection 变为多字符（用户选中文本）、`selectedRange().location != expectedCursor`（用户移动了光标）→ 静默丢弃镜像 buffer 和候选窗，本次按键照常处理。因为 SwiftType 从未写入客户端，stale 清理永远安全，没有 marked-range 回滚问题。

### 4.3 生命周期保护（`InputControllerLifecycle.swift` / `InputControllerComposition.swift`）

镜像模式下 **lifecycle 绝不能把 buffer 再插入一遍**（字母已在 field 里，插入即重复）：

- `commitCompositionBuffer` / `commitCompositionForLanguageSwitch`：检测 `state.mirrorsClientText` 或客户端属于透明预测 → `discardMirroredComposition()`（只清状态），否则走原 inline commit。
- `deactivateServer` / `commitComposition` / `cancelComposition` 均经由上述入口，自动安全。
- `composedString` / `originalString` 在镜像模式下返回 `""`，确保系统永远看不到 composition。
- `discardMirroredComposition()` 是唯一清镜像入口：buffer、`mirrorsClientText`、`compositionBaseline`、`expectedCursor`、`compositionClientBundleID`、候选窗全部清空。

### 4.4 状态字段（`Input/State/InputState.swift` 新增）

- `mirrorsClientText: Bool` —— 当前 buffer 是镜像而非真实 composition
- `compositionBaseline: NSRange?` —— 首字母时的光标位置，用于纠正型替换的 typed region
- `expectedCursor: Int?` —— 预期光标（UTF-16 计数），用于 stale 检测；客户端返回 `NSNotFound` 时为 nil，stale 光标检查跳过
- `compositionClientBundleID: String?` —— 首字母时的 bundle ID
- `reset()` 清空以上全部字段

### 4.5 与 inline 路径的隔离

`handleKey` 中 `.inline` 分支原样进入原有逻辑；透明预测是独立扩展文件 + 独立私有方法，不共享 `handleCharacterInput`/`handleBackspace` 等可变状态的实现，避免两条路径互相污染。普通应用行为完全不变（`InputControllerEventRoutingTests` 原有断言全部保持通过）。

## 五、测试状态

全部通过（`xcodebuild -scheme SwiftType -configuration Debug test`，TEST SUCCEEDED，全量 491 个用例，policy 重构后复验）：

- `Tests/Input/InputClientPolicyTests.swift`（新增）：三种模式判定、passthrough 优先级、Chromium 家族免逐一列举、企业微信 helper 前缀、UserDefaults 动态追加坏应用、TextEdit/Safari/Xcode 保持 inline。
- `Tests/Input/InputControllerTransparentPredictionTests.swift`（新增）：字母透传无 marked text、WeCom 镜像、Backspace 同步、Caps Lock 只丢镜像不插入、deactivate 不重复插入、stale 光标后重新起词、literal space 透传、数字选词只插 suffix、纠正型一次性 prime+commit（验证 marked range 覆盖已输入区域）、Cmd 组合丢弃、方向键丢弃。
- `Tests/Input/InputControllerEventRoutingTests.swift`：原 Caps Lock/终端/VS Code 行为回归全部保持。
- `Tests/Input/InputControllerTests.swift`：`InputState.reset()` 清空全部新字段的断言已补。
- `InputState.swift` 因新增 `NSRange` 需 `import Foundation`；`composedString` 的 `MainActor.assumeIsolated` 闭包需显式标注 `() -> String`（否则推断为 Any 违反 Sendable）。

已知无害警告：测试 helper 中 MainActor 隔离警告（与现有测试文件一致的模式）。

## 六、下一步（按顺序）

1. **构建安装**：`sh scripts/install.sh`（Release、原位 rsync、lsregister、重启 `TextInputMenuAgent`/`TextInputSwitcher`）。
2. **手工验收**（只能用户在 GUI 做）：
   - Edge 和企业微信：输入半个单词时按中/英键 → 输入源立即切换，已输入字母保留在 field 中。
   - Space / Return / 数字选词 → 只产生一次完整单词（suffix 不重复、不双空格）。
   - Backspace → 每次只删一个字符，候选窗同步收缩。
   - 移动光标或选择文本后再按键 → 旧候选被静默清除，新输入从新位置起词。
   - 若某 CEF 客户端（如企业微信部分 Flutter 输入框）`selectedRange` 行为异常 → 观察是否出现选词不生效；不影响 Caps Lock 切换本身。
3. **若某客户端透明预测仍不稳定**：最终 fallback 是把它加入 passthrough 列表（完全透传、无候选），不要用全局事件监听或强制切换输入源。
4. **HUD 旧双箭头图标**：注销/重新登录后复测（`CursorUIViewService` 缓存可能只在登录会话重建时刷新）。注意：`xcodebuild test` 每次都会 `lsregister` DerivedData 的 Debug 包，可能继续污染图标缓存；测试后应重装 Release 或直接注销重登。磁盘上还有 `build/Debug/SwiftType.app`、`build/Release/SwiftType.app` 和 DerivedData 的旧构建（mdfind 确认），如注销后 HUD 仍错，安全删除这些旧包再复测。受"不使用 `lsregister -u`"约束，未注销旧注册。

## 七、约束与决定（不要违反）

- 不处理浏览器 Web CLI 特例。
- 不增加 per-app 菜单开关（用 UserDefaults 数组代替，见 4.1）。
- VS Code 整个应用保持 passthrough（含内置终端）。
- 不使用 `TISEnableInputSource`、`TISDisableInputSource`、`TISSelectInputSource`、`lsregister -u` 强制修改系统输入源/LaunchServices 状态。
- 不实现"消费字母但不设 marked text"的普通 no-inline：Chromium 会把原始按键重投递给网页，导致 "hheell" 双写和双删（Chromium gate：`_hasMarkedText || _textToBeInserted.length() > 1` 才 mask）。
- 不使用 `NSWorkspace.frontmostApplication` 猜测客户端；以 `client.bundleIdentifier()` 为唯一事实来源（hallelujah 同款结论：frontmost 猜测曾导致非目标应用被误透传）。
- 输入源元数据必须保持 Latin 英文：`TICapsLockLanguageSwitchCapable = true`、`TISIntendedLanguage = en`、`tsInputMethodCharacterRepertoireKey = ["Latn"]`、`tsInputMethodIconFileKey = SwiftTypeInputSourceIcon.png`（`Tests/App/ConstantsTests.swift` 有断言）。
- 工作区包含大量此前未提交的改动（英文专用化、删除 KenLM/多语言/SettingsManager、隐私日志、纵向候选窗等），不得误删或回滚无关修改。

## 八、改动文件清单（本次 transparent-prediction 相关）

新增：

- `Input/InputClientPolicy.swift` —— 三模式策略 + Chromium 启发式 + UserDefaults 扩展
- `Input/Controller/InputControllerTransparentPrediction.swift` —— 镜像预测全部按键语义
- `Tests/Input/InputClientPolicyTests.swift`
- `Tests/Input/InputControllerTransparentPredictionTests.swift`
- `HANDOFF.md` —— 本文件

修改：

- `Input/Controller/InputController.swift` —— 常量改为引用 policy；`usesTransparentPrediction` 薄封装；架构表更新
- `Input/Controller/InputControllerKeyHandling.swift` —— Caps Lock 分支区分镜像/inline；`handleKey` 按 `InputClientPolicy.mode` 三分支路由
- `Input/Controller/InputControllerComposition.swift` —— `commitCompositionBuffer`/`commitCompositionForLanguageSwitch` 镜像模式只清状态
- `Input/Controller/InputControllerLifecycle.swift` —— `composedString`/`originalString` 镜像模式返回空串
- `Input/State/InputState.swift` —— 新增 4 个镜像状态字段；`import Foundation`
- `Tests/Input/InputControllerTests.swift` —— `InputStateTests` 覆盖新字段
- `SwiftType.xcodeproj/project.pbxproj` —— 注册以上全部新文件（Input 分组 + 两个 target 的 Sources；TP*/CP* ID 已核对无重复）
- `README.md` —— 修正测试命令为 `-scheme SwiftType`（旧文档引用了不存在的 `SwiftTypeTests` scheme）；架构图补入 `InputClientPolicy` 与透明预测；新增 "Per-app compatibility" 一节（含 `defaults write ... transparentPredictionBundleIdentifiers -array-add` 用法）

验证状态（2026-09-04 复核）：

- 全量测试：491 个用例全部通过，TEST SUCCEEDED。
- `git diff --check` 通过（无空白错误）。
- `xcodebuild -list` 确认 scheme 只有 `SwiftType`（README 旧命令已修正）。
- pbxproj 中 `InputClientPolicy.swift`、`InputControllerTransparentPrediction.swift` 及两个测试文件在 PBXBuildFile/PBXFileReference/Group/Sources 四处均已注册（app + test 两个 target）。

此前会话已完成（保持不动）：`.flagsChanged` 注册、终端/VS Code 透传、纵向候选窗默认、`SwiftTypeInputSourceIcon.png` 资源与 Info.plist 键、`scripts/install.sh` 的 agent 重启。

## 九、诊断记录

- 实时日志：`/var/folders/yt/ngt31b5x55zgdf8lj7xwqqt40000gn/T/opencode/swifttype-caps.log`（Edge 中按中/英键无 `Caps Lock event received` —— 根因证据）。
- 日志命令：
  ```bash
  /usr/bin/log stream --style compact --level info \
    --predicate 'subsystem == "com.matthew.inputmethod.SwiftType" AND category == "InputController"'
  ```
- Chromium gate 参考：`content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm`（`interpretKeyEvents` 后按 `_hasMarkedText || _textToBeInserted.length() > 1` 决定 mask 或转发原键）。
- 参考项目：`/Users/developer/coding/hallelujahIM`（`TerminalPassthrough` 策略类模式）、Squirrel `app_options`/`force_marked_text_for_direct_commit`、fcitx5-macos dummy preedit、macSKK Direct Mode。

## 十、快速上手（下次会话从这里开始）

1. `sh scripts/install.sh` 安装新 Release。
2. 让用户在 Edge/企业微信执行第六节验收场景。
3. 若验收失败，先读 `Input/Controller/InputControllerTransparentPrediction.swift` 的 stale 检查与 `commitTransparentWord` 三路径，再按客户端实际行为调路径优先级；不要回退到"消费按键 + 无 marked text"。
4. HUD 图标问题走第六节第 4 步。
