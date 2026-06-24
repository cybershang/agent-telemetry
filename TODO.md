# agent-telemetry TODO

## 📝 后续版本发布待办

### 发布 `cybershang/agent-telemetry@0.1.4`
- **状态**：🟡 进行中
- **原因**：自 `0.1.3` 以来 accumulated 变更：新增 `.env.example`、OTLP 失败非致命处理（`safe_exporter`）、清理 `unused_package` warning、新增 `docs/instrumentation.md` 插桩指南。
- **步骤**：
  1. ✅ 在 `agent-observability/agent-telemetry/moon.mod` 中将版本号 bump 到 `0.1.4`
  2. ⬜ 同步修改到独立仓库 `cybershang/agent-telemetry`
  3. ⬜ 在独立仓库打 tag `v0.1.4` 并 push，触发 publish action
