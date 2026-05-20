# Ent 代码生成

> 索引：2 条 pitfall

---

## 删除 ent schema 时不要先删 generated package

**何时撞见**：删除某个 ent schema 后运行 `go generate ./ent` 报 `entc/load: no required module provides package .../ent/<name>`。
**为什么**：ent 生成前会先加载当前 `ent` 包；如果 generated package 已被手动删掉，但 `client.go` 等旧产物仍引用它，加载阶段就失败，生成器没机会重建。
**怎么办**：先只改/删 `ent/schema/*.go`，保留旧 generated 文件到 `go generate ./ent` 成功；生成完成后再由 ent 输出统一删除旧 package。不要用 `go mod tidy` 修这个错误。

## 重命名 ent JSON 依赖的 domain 类型要过桥

**何时撞见**：重命名 `field.JSON(..., domain.Xxx{})` 依赖的 domain 类型后，`go generate ./ent` 先报旧生成代码里的 `undefined: domain.OldXxx`。
**为什么**：ent 生成前会加载当前 generated `ent` 包，旧产物仍引用被删的 domain 类型，生成器还没机会输出新代码。
**怎么办**：在 domain 里临时加 `type OldXxx = NewXxx` alias，跑 ent 生成成功后立刻删 alias，再跑编译确认没有旧名残留。