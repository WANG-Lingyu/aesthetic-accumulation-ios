# 审美积累（iPhone 版）— 项目工作指引

## 项目定位
iPhone 端「审美积累」App：素材册子 + 穿搭 + 日历 + 我的，后期加社区。当前第一阶段：**骨架 + 素材**。

## 开发原则
- 小步、稳定推进，逐里程碑验收（M0→M4…），每步：编译通过 → 模拟器验证 → 更新开发日志 → 汇报，确认后再进下一步。
- **AI 本地优先**（抠图用 iPhone Vision）；**数据统计先只放图标**；Mac 版与 iPhone 版数据独立不互通。

## 目录结构
- `Package.swift` + `Sources/AestheticApp/`：iOS SwiftUI 源码
- `docs/`：标准文档（需求 / 计划）
- `开发日志/`：每日自动维护

## 工作约定
- 主题色：底色 `#F8F5EE`，主色 `#2A3B4E`
- 底部菜单：素材 / 搭配 / 日历 / 我的 + 中间「＋」

## 构建与运行
- 命令行构建（需指定 Xcode 工具链）：
  `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- 编译校验：
  `swift build -Xswiftc "-sdk" -Xswiftc "$(xcrun --sdk iphonesimulator --show-sdk-path)" -Xswiftc "-target" -Xswiftc "arm64-apple-ios17.0-simulator"`
- 真机/模拟器运行：Xcode 打开 `Package.swift`，选 iPhone 模拟器 Run

## 每一步要做的事
1. 写代码（遵守主题色与结构）
2. 编译通过
3. 模拟器验证里程碑验收标准
4. 更新 `开发日志/`（当日 + 待办事项）
5. 向用户汇报，等待确认
