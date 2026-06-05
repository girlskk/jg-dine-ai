# Ent 代码生成

> 索引：2 条 pitfall

---

## 改 schema 前先保住旧 generated 包能被加载

**何时撞见**：删除 schema、重命名 `field.JSON(..., domain.Xxx{})` 类型后，`go generate ./ent` 先报旧 `ent` 产物里的 import/type 不存在。
**为什么**：ent 生成前会加载当前 generated `ent` 包；旧 `client.go`、旧 schema package、旧 JSON 类型引用必须先能编译，生成器才有机会输出新代码。
**怎么办**：不要先手删 generated package；重命名 domain 类型时临时保留 `type OldXxx = NewXxx` alias。跑通 `go generate ./ent` 后再删过桥 alias/旧产物并重新编译。不要用 `go mod tidy` 修加载失败。

---

## `.Only()` 在多行结果时报 not-singular，不要用它做 claim-one

**何时撞见**：`SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1` 查询实际生成 `LIMIT 2`，表里有 ≥2 条匹配行时 `.Only()` 返回 "not singular" 错误，claim 静默失败。
**为什么**：ent 的 `.Only(ctx)` 内部强制把 limit 改为 2，用于区分「0 行 / 1 行 / 多行」三种情况；claim-one 语义只要拿一条，不能用唯一性语义。
**怎么办**：claim-one 场景一律用 `.First(ctx)`（生成 `LIMIT 1`）；`.Only()` 只用于期望数据库里恰好存在 1 条的强约束场景。
