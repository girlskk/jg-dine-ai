# 桌台模块知识

> 来源 threads: dine-table-qrcode-h5-link, backend-dine-table-qrcode-config-split, dine-table-qrcode-export-url

## 二维码内容

- 二维码内容为 H5 完整链接：通过 `url.JoinPath(CustomerBaseURL, TableQRCodePagePath)` + `params=<tableID>` 生成
- `CustomerBaseURL` 在共享 `domain.AppConfig`（所有服务统一提供）
- `TableQRCodePagePath` 也在 `AppConfig`，默认值 `peopleCount`（`default:"peopleCount"` tag）
- 二维码生成逻辑留在 `usecase/dinetable`，`backendfx` 不承载业务逻辑
- 缺配置时直接返回错误，避免静默生成错误二维码

## 导出

- 桌台码导出走异步 Excel 任务（handler build payload → usecase create task → ProcessTask export）
- 导出表头：`code`、`name`、`capacity`、`qrcode`
- `qrcode` 列输出实际 URL，不是对象 key。通过 `Storage.GetURL(ctx, key)` 转换
- `DineTable.QRCodeURL` 字段名使人误以为存的是 URL，实际存的是对象 key。导出场景必须显式转 URL
- 桌台码导出参与 300 条阈值分流

## 配置层约束

- 当共享 usecase 需要新增配置依赖时，先检查是否所有服务已统一提供
- 稳定默认值不要重复配置在 env 中，制造漂移点
