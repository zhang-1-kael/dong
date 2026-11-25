# Dòng 同步服务

给「壁纸跟着账号走」用的最小后端。零依赖，一个 Node 进程 + 一个目录。

## 它做什么

- 邮箱 + 密码登录（scrypt 加盐，不存明文）
- 每个账号一份壁纸清单（文件名、大小、sha256、顺序、网页壁纸地址）
- 壁纸文件本身也存着（换设备时直接下载，不依赖原链接还活着）
- 每账号默认 2 GB 配额，单文件上限 512 MB

不做什么：不记录你的使用行为（那是 App 里另一套匿名统计，可以单独关掉）。

## 跑起来

```bash
cd sync-server
node server.js            # 监听 :8787，数据写到 ./data
```

首次运行会建 `data/`，直接 `tar` 走就是完整备份。

### 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `SYNC_PORT` | `8787` | 监听端口（优先读这个，托管平台注入的就是它） |
| `PORT` | `8787` | 兼容写法，`SYNC_PORT` 没设时生效 |
| `DATA_DIR` | `./data` | 数据目录 |
| `DONG_QUOTA_GB` | `2` | 每账号存储上限 |
| `DONG_MAX_ASSET_MB` | `512` | 单个壁纸文件上限 |
| `DONG_TOKEN_DAYS` | `60` | 登录有效期（天） |
| `DONG_STORAGE` | `disk` | 壁纸文件存哪：`disk` 本地磁盘 / `gateway` 官网存储网关 |
| `SYNC_GATEWAY_BASE` | `https://dongisgood.coze.site` | gateway 模式的网关卡地址（与官网同域） |
| `SYNC_INTERNAL_TOKEN` | 无 | gateway 模式的内部凭证，**由部署方注入，仓库里不存** |
| `DONG_GATEWAY_DOWNLOAD` | `redirect` | `redirect` 直接 302 给客户端直连对象存储；`pipe` 由本进程转发 |
| `DONG_GATEWAY_STRICT` | 未设 | 设 `1` 时，gateway 自检失败直接退出（默认只报错不退出） |

### 放到服务器上

最省事的三种：

1. **一台 VPS**：`node server.js` 挂 systemd，前面用 Caddy / Nginx 反代到 443。
   ```caddy
   sync.yourdomain.com {
       reverse_proxy 127.0.0.1:8787
   }
   ```
2. **Render / Railway / Fly.io**：Start Command 填 `node server.js`，
   挂一个持久卷到 `/data`，并把 `DATA_DIR=/data`。
3. **家里的 Mac / NAS**：同理，反代出去即可（注意上行带宽和电费）。

上线之后，把 App 的 `Info.plist` 里加一个键：

```xml
<key>SyncBaseURL</key>
<string>https://sync.yourdomain.com</string>
```

没填 `SyncBaseURL` 就退回 `ApiBaseURL`（现在指向官网）；两个都没有就视为未配置，
App 里「登录」会直接提示不可用，不会往猜的域名发密码。

## 存储模式

| 模式 | 壁纸文件位置 | 适用 |
|---|---|---|
| `disk` | `DATA_DIR/users/<uid>/assets/<id>.bin` | 联调用。**宿主磁盘可能被平台清理，别给真实用户用** |
| `gateway` | 官网内部网关 `/api/sync-storage/*` → 平台对象存储 | 正式环境 |

`gateway` 模式的几个行为：

- 上传：把入站请求**管道**给网关，边传边算 sha256，不落临时文件；返回的 key（形如 `sync/{uid}/{aid}_a6382452`）
  记在 `users/<uid>/assets.json`，assetId → key 一一对应
- 下载：向网关换 1 小时签名直链，再 **302** 给客户端，512MB 不经过本进程
- 覆盖上传：网关每次上传都会追加新 UUID，同名覆盖后旧对象会被主动删掉，不白占配额
- 删除：按映射找到 key 后删网关对象，同时清掉映射
- 用量：网关的 list 不返回文件大小，`/api/me` 的 `usedBytes` 改为按清单里 `bytes` 汇总
- 启动自检：向网关发 `list?prefix=sync/selfcheck/`，失败时**日志明确报错 + `/healthz` 返回 503**，
  但默认**不退出进程**（托管平台会反复重启，日志反而更难查）；需要「起不来就别起」时设 `DONG_GATEWAY_STRICT=1`

## 限流

内置一层很粗的按 IP 限流，防止公网被撞库：

| 接口 | 上限 |
|---|---|
| `POST /api/auth/register` | 5 次 / 分钟 / IP |
| `POST /api/auth/login` | 12 次 / 分钟 / IP |

超了返回 `429 {"error":"试得太快了，等一分钟再试"}`。

**必须让反代透传 `X-Forwarded-For`**：服务端优先用它判断客户端 IP，
否则所有请求都来自反代自己的地址（`127.0.0.1`），5 次注册之后会把所有人一起挡住。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/healthz` | 探活 |
| POST | `/api/auth/register` | `{email,password}` → `{token,...}` |
| POST | `/api/auth/login` | 同上 |
| POST | `/api/auth/logout` | 作废当前 token |
| POST | `/api/auth/password` | 改密码 `{oldPassword,newPassword}`；成功后作废其它设备令牌，当前设备保留 |
| GET | `/api/me` | 邮箱、配额、已用字节 |
| GET | `/api/sync/manifest` | 清单（含 `rev`） |
| PUT | `/api/sync/manifest` | 写清单，带 `if-match: <rev>`，对不上返回 409 |
| PUT | `/api/sync/asset/:id` | 上传壁纸（octet-stream） |
| GET | `/api/sync/asset/:id` | 下载壁纸 |
| DELETE | `/api/sync/asset/:id` | 删除（客户端删壁纸后回收配额） |

`id` 规则：视频是 `v-<文件名>`，网页壁纸是 `w-<stream id>`。清单里的删除是墓碑
（`deleted: true`），保留 30 天，避免另一台设备把刚删的又推回来。

## 安全边界

- 密码用 `scrypt`（N=16384 默认）加盐，`timingSafeEqual` 比对
- token 是 32 字节随机数，服务端只存它的 sha256；有效期 60 天
- 所有壁纸读写都带 `authorization: Bearer`，且只能碰自己 `userId` 目录下的文件
- 上传路径做白名单清洗（`[A-Za-z0-9._-]`），杜绝 `../`
- 没有管理员接口、没有跨账号读取

## 已知限制（v1 有意为之）

- 冲突策略是「谁更新谁赢」，不保留历史版本
- 重命名等于删一条加一条（App 用文件名当身份），会重新上传一次
- 没有邮箱验证 / 找回密码；账号在服务端 `data/accounts.json` 里，忘了密码得手工删那条重注册
- 不加密存储：文件在服务器磁盘上是原样 mp4（传输靠 HTTPS）
