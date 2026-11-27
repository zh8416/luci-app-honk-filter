# luci-app-honk-filter

Honk 原生风格的**广告拦截 + DNS 分流**管理页面，规则直接写入 Honk 自身配置。

> 不安装 AdGuardHome，不安装 mosdns，不启动任何额外 DNS 进程，不叠加任何一层。
> 广告过滤由 Honk 核心的 `domain(...) -> block` 完成，DNS 分流写入 Honk 的 `dns {}` / `global {}`。

这是 `kenzok8/openwrt-honk` 的 fork 中新增的**独立软件包**，上游的 `honk/`、`luci-app-honk/` 一个文件都没有改动。

---

## 功能（第一版）

### 服务 → Honk → AdBlock
- **状态**：引擎开关、当前生效域名数、最后更新时间
- **规则源**：添加在线 URL 规则（自动/ABP/hosts/纯域名格式）、启用/禁用、手动更新、失败计数
- **离线规则包**：粘贴离线规则文本导入
- **自定义规则 / 白名单**：手工增删域名
- **更新日志**：下载与重建记录

### 服务 → Honk → DNS
- 国内 DNS（default upstream）、远程 DNS（remote upstream）
- Bootstrap resolver、默认回退（fallback）
- DNS 缓存开关、IPv6/AAAA 开关
- 一键恢复默认

所有写操作都经过 `honk-core config validate`，失败自动回滚，不会破坏正在运行的配置。

---

## 安装

依赖 `honk` 与 `luci-app-honk`（会随包自动安装），与 `luci-app-adguardhome` 冲突。

把本目录放进 OpenWrt/ImmortalWrt 25.12 的 package feed，然后：

```sh
make menuconfig   # LuCI → Applications → luci-app-honk-filter
make package/luci-app-honk-filter/compile -j$(nproc)
```

或 apk/ipk 直接安装编译产物。安装后刷新浏览器，`服务 → Honk` 下出现 **AdBlock** 和 **DNS** 两个菜单。

---

## 规则语法支持

| 规则形式 | 支持 |
|---|---|
| 纯域名 `ads.example.com` | ✅ |
| hosts `0.0.0.0 ads.example.com` | ✅ |
| ABP `||ads.example.com^` | ✅ |
| 白名单 `@@ads.example.com` | ✅ |
| 正则 `/ads[0-9]+/` | ❌ 跳过 |
| `$third-party` / `$dnsrewrite` 等修饰符 | ❌ 跳过 |

不支持的规则会在解析时跳过，不会导致构建失败。

---

## 工作原理

- 规则下载到 `/etc/honk/filter/sources/*.txt`
- 解析、去重、套用白名单后，生成 `domain(...) -> block` 规则
- 通过**标记块**写入 `/etc/honk/config.dae` 顶层 `routing {}` 开头：

  ```
  # honk-filter:adblock-begin
  domain(ads.example.com, ...) -> block
  # honk-filter:adblock-end
  ```

- 用标记块而不是新增 include 文件，是为了不破坏 Honk 的 `config_owner()` 布局检测（它只认 `secrets.dae` / `system.dae`，任何额外 include 都会让配置被判为 `unknown`）。
- 每次写入：生成候选 → `honk-core config validate` → 原子替换 → `/etc/init.d/honk reload`；任一步失败自动恢复旧文件。

---

## 与上游同步（重要）

所有新增代码都在 `luci-app-honk-filter/` 目录，**上游文件零改动**，所以同步上游不会产生合并冲突。

```sh
# 首次添加上游
git remote add upstream https://github.com/kenzok8/openwrt-honk.git

# 查看差异（不改动）
scripts/sync-upstream.sh

# 应用同步：merge 上游到 main，再把 filter-v1 rebase 到 main
scripts/sync-upstream.sh --apply
```

`sync-upstream.sh` 会同时做运行时兼容性自检。

### 每次上游更新后的复检清单

本包对上游有少量**运行时接口依赖**，上游改了这些地方需要重新验证：

1. `config.dae` 仍有 `dns { upstream { default: ... -> direct / remote: ... -> proxy } }` 结构 → 影响 `filter.sh` 的 `dns_apply()`
2. `config.dae` 仍有顶层 `routing {` 块 → 影响标记块注入
3. `bootstrap_resolver:` 字段仍在 `global {}` 中 → 影响 DNS bootstrap 设置
4. `/etc/init.d/honk reload` 仍可用 → 影响所有配置生效
5. `lifecycle.sh` 仍导出 `config_owner()` / `config_include_entries()` → 影响配置布局判断

这些检查已写进 `scripts/sync-upstream.sh`，会自动提示。`dns_apply()` 和 `render_config()` 是本包唯一与上游配置格式耦合的两个函数，如需适配只改这两处。

---

## 目录结构

```
luci-app-honk-filter/
├── Makefile
├── root/
│   ├── etc/config/honk-filter                    # UCI 默认配置
│   ├── etc/uci-defaults/90-honk-filter           # 首次安装初始化
│   ├── usr/libexec/rpcd/honk-filter              # 独立 ubus 后端
│   ├── usr/share/luci/menu.d/...                  # 菜单
│   ├── usr/share/rpcd/acl.d/...                   # 权限
│   └── usr/share/honk-filter/
│       ├── filter.sh                              # 规则引擎 + 配置写入
│       ├── update.sh                              # 在线规则下载
│       └── cron.sh                                # 自动更新 cron
└── htdocs/luci-static/resources/view/honk-filter/
    ├── rpc.js / adblock.js / dns.js / filter.css
```

---

## 已知限制（第一版）

- AAAA / HTTPS-SVCB / 防 DNS 泄露 / Apple 域名优化等高级开关尚未实现（部分需要 honk core 支持）
- 自动更新 cron 固定为每天 03:00，暂未做每源独立周期
- 离线规则包通过粘贴文本导入，未做文件上传控件
- 暂不提供查询日志与统计图表（这是 AdGuardHome 原生面板的强项，如需请另行安装）

License: GPL-3.0-only（与上游一致）
