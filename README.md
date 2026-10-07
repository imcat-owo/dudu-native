# dudu-native

嘟嘟原生 iOS App（Swift / SwiftUI）。

路线（2026-10-07 零件论）：**只借 OpenMinis 的引擎零件**（聊天内核、Providers/API 分组、TTS、MCP、iSH、浏览器引擎、备份、审批门、纸条机制），界面一根不拿，产品层全部做嘟嘟自己的。

计划书：`~/workspace/dudu-native-rewrite/parts-plan.md`（本地）。

## 当前状态

- P0：工程骨架（本提交）

## 构建

CI（`.github/workflows/ios.yml`）在每次 push 到 main 时打出 unsigned IPA，产物在 Actions 页面下载，用全能签/自签安装。

本地需要 Xcode 16+，macOS。
