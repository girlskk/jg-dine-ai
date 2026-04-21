# Thread: customer 会员验证码入口与缓存 key 收口

> 日期: 2026-04-13
> 标签: #customer #sms #verify-code #auth #reflect

## Context

前端需要 customer 端“修改支付密码验证码”接口。最终范围只落在短信发送入口本身，但在动手前先确认了这条链路的两个关键风险：

1. customer 侧只有匿名登录验证码接口，没有 member-only 的通用验证码入口；
2. 验证码缓存 key 直接拼 `country_code-phone`，而历史校验逻辑会把区号补 `+`，发送和读取可能命中不同 key；

过程中也发现 customer 支付密码接口本身存在 member 边界问题，但用户明确要求这次不要修改 member 相关代码，因此最终只交付短信入口和缓存 key 收敛，不扩 scope。

## 关键决策

1. 通用验证码接口只接收 `biz_type`，不允许前端在已登录场景继续上传手机号或商户 ID。

   原因：修改支付密码属于“本人已登录操作”。如果还让前端传手机号，这个接口本质上就是一个可枚举、可越权触发的短信发送器。

2. 登录验证码和 member-only 验证码拆成两个入口，而不是在同一路由里按 body 决定是否鉴权。

   原因：customer auth 中间件的 `NoAuths()/GuestAuths()` 是静态路由声明机制，不适合做“同一路由、不同 biz_type、不同权限级别”的动态分流。路由分开才能保持鉴权边界清晰。

3. 验证码缓存 key 的区号统一做内部归一化，并强制补齐前导 `+`，只影响 Redis key，不改实际发送给短信服务商的区号值。

  原因：外部短信供应商对区号格式是否接受 `+60` 并没有在这次任务里被验证，贸然改发送协议是在赌。把归一化限制在缓存 key 层，可以修复“能发不能验”的问题，又不引入第三方协议风险；统一补 `+` 还能满足现有业务读取时对区号格式的要求。

## 最终方案

- `api/customer/handler/sms.go`
  - 保留匿名 `POST /sms/send-login-code`；
  - 新增 member-only `POST /sms/send-verify-code`；
  - 新接口只接 `types.SendVerifyCodeReq{biz_type}`，当前仅放行 `modify_pay_password`；
  - 商户、区号、手机号统一从 `CustomerUserContext` 里的当前 member 读取。

- `api/customer/types/sms.go`
  - 新增 `SendVerifyCodeReq`。

- `domain/sms.go`
  - 新增 `BuildSMSVerifyCodeKey` / `BuildSMSVerifyCodeRecentKey`；
  - 统一在 key 层裁剪空格并补齐区号前导 `+`；
  - `GetSentVerifyCode` 改为复用共享 key helper。

- `usecase/sms/send_sms.go`
  - 发送验证码和一分钟内重复发送判断统一改走共享 key helper。

- `api/customer/docs/*`
  - 通过 `go generate ./...` 重建 Swagger 产物。

验证：

- `cd /Users/rrr/go/src/dine-api && go test ./api/customer/... ./usecase/sms ./domain/...` ✅
- `.github/acceptance/` 当前没有 customer 验收脚本，无法补跑接口级 acceptance。✅ 已确认缺口，未伪造验证。

## 踩坑与偏差

1. 中途确认到 customer 支付密码接口本身有 member 边界问题，但用户明确要求不改 member 相关代码，所以这里必须收住手，不能借“顺手修一下”扩大范围。

2. 验证码区号格式问题不在新接口里显式暴露，但它是共享缓存 key 的系统性问题。只修 handler 会把旧 bug 原样复制到新接口。

3. 本次没有把修改支付密码的“验证码校验”直接接入 member 流程。用户当前只要求发码入口，业务侧后续应继续通过 `domain.GetSentVerifyCode` 在自己的修改密码流程里校验。

## 可复用模式

1. 对“已登录本人操作”的短信验证码接口，前端只应传业务类型，手机号和商户必须从当前登录上下文取，不能继续信任客户端入参。

2. 当验证码 key 同时被多个入口发送和多个业务读取时，key 拼装必须收敛到共享 helper；任何一个入口自己拼 key，迟早会出现发送/读取不一致。