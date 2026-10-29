# kcptun-script

> Kcptun 服务端一键安装与管理脚本 · 当前版本 **v38**

本脚本用于在一台 Linux 服务器上快速部署 [Kcptun](https://github.com/tobycroft/kcptun) 服务端：自动下载主程序、生成配置、托管为系统服务，并提供多实例管理与在线更新能力。

---

## 新版与旧版的核心区别

本次重构（v27 起）与旧的 Supervisor 版本相比，变化集中在**依赖、托管方式与升级体验**三块：

| 维度 | 旧版（Supervisor） | 新版（v31） |
| --- | --- | --- |
| 运行依赖 | Python + pip + Supervisor | **无额外依赖**，systemd / SysVinit 原生托管 |
| 进程管理 | `supervisord` + `supervisorctl` | `systemctl` / `service`，每实例一个 unit 或 init 脚本 |
| 安装依赖 | wget、gawk、tar、python、python-pip | wget（或 curl）、gawk、jq |
| 支持架构 | amd64 / 386 | **amd64 / 386 / arm64 / arm** |
| 主程序获取 | tar.gz，从 Release 正文解析哈希 | **裸二进制 + `checksums.txt` 校验** |
| jq | 固定下载 1.5 | **系统软件包优先**，缺失时下载 1.7.1 |
| 更新能力 | 仅 `update` | **`check` 只查询** + `update` 执行，脚本更新带 SHA256 校验 |
| 防火墙 | firewalld / iptables，会尝试启动防火墙 | **firewalld / ufw / iptables**，且不会启动或重启已关闭的防火墙 |
| 旧版升级 | 需要重新配置 | **自动识别并迁移**，沿用原配置，无需重配 |

一句话总结：**依赖更少、架构更全、升级不再要求重新配置。**

---

## 主要特性

- **一键安装**：自动下载主程序、校验 SHA256、生成配置并注册为系统服务
- **交互式配置**：端口、加速地址、密码、加密方式、加速模式等均有默认值，一路回车即可完成
- **多实例管理**：添加、删除、重配多个实例，实现多端口同时加速
- **服务托管**：systemd unit（SysVinit 环境下为 init 脚本），支持开机自启与崩溃自动拉起
- **旧版平滑迁移**：检测到 Supervisor 部署时自动迁移，不需要重新配置
- **下载加速**：支持 `GITHUB_PROXY`、`KCPTUN_RELEASES_API`、`KCPTUN_SCRIPT_BASE_URL` 接入镜像
- **客户端输出**：安装完成后直接生成客户端 JSON 配置与手机端参数字符串

---

## 快速开始

### 支持的系统

| 系统 | 版本 | 服务管理 | 防火墙适配 |
| --- | --- | --- | --- |
| Ubuntu | 20.04 / 22.04 / 24.04 | systemd | ufw |
| Debian | 10 / 11 / 12 / 13 | systemd | iptables（nft 后端） |
| CentOS | 7 / Stream 8 / Stream 9 | systemd | firewalld |
| RHEL / Rocky Linux / AlmaLinux | 8 / 9 | systemd | firewalld |
| Fedora | 30 及以上 | systemd | firewalld |
| Oracle Linux | 7 / 8 / 9 | systemd | firewalld |
| Photon OS | 3 及以上 | systemd | iptables |

- 架构：x86_64（amd64）、x86（386）、arm64、arm
- 权限：需要 root
- 服务管理：systemd 优先，无 systemd 时回退 SysVinit
- 运行依赖：wget（或 curl）、gawk、jq，脚本会自动安装，**无需 Python / pip / Supervisor**

> 未列出的衍生发行版，只要使用 systemd + apt/dnf/yum 包管理，通常也可以直接运行。

### 安装

```sh
# 使用 wget
wget --no-check-certificate -O kcptun.sh https://github.com/TuuzNet/kcptun-script/raw/main/kcptun.sh

# 或使用 curl（最小化系统可能只有 curl）
curl -fsSL https://github.com/TuuzNet/kcptun-script/raw/main/kcptun.sh -o kcptun.sh

sh kcptun.sh
```

国内服务器可加下载加速：

```sh
GITHUB_PROXY='https://ghfast.top/' sh kcptun.sh
```

脚本需要访问 GitHub 获取版本信息与二进制，下载失败会自动重试 3 次。

---

## 常用命令

| 命令 | 作用 |
| --- | --- |
| `sh kcptun.sh` / `install` | 安装；已安装时进入管理菜单 |
| `sh kcptun.sh uninstall` | 卸载服务与配置 |
| `sh kcptun.sh check` | 仅检查脚本与 Kcptun 是否有新版本 |
| `sh kcptun.sh update` | 检查并执行更新 |
| `sh kcptun.sh migrate` | 将旧版 Supervisor 部署迁移到 systemd / SysVinit |
| `sh kcptun.sh manual [tag]` | 安装指定 Kcptun 版本（如 `v20160904`） |
| `sh kcptun.sh add` | 添加一个实例 |
| `sh kcptun.sh reconfig <id>` | 重新配置实例 |
| `sh kcptun.sh show <id>` | 查看实例配置 |
| `sh kcptun.sh log <id>` | 实时查看实例日志 |
| `sh kcptun.sh del <id>` | 删除实例 |
| `sh kcptun.sh losstest <id>` | 丢包测试（需要客户端同版本 CLI 配合） |
| `sh kcptun.sh help` | 查看帮助 |

实例 `id` 省略时默认为 1，对应服务名 `kcptun`，其余为 `kcptun2`、`kcptun3`…

服务操作：

```sh
# systemd
systemctl {start|stop|restart|status} kcptun<id>
systemctl {enable|disable} kcptun<id>

# SysVinit
service kcptun<id> {start|stop|restart|status}
```

---

## 配置参数

交互式配置会依次引导以下参数，均有默认值：

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| listen | 监听端口，支持范围如 `30000-35000` | `29900` |
| target | 加速地址（主机名 / IPv4 / IPv6）与端口 | `127.0.0.1:12984` |
| key | 连接密码，两端必须一致 | `very fast` |
| crypt | aes / aes-128 / aes-192 / salsa20 / blowfish / twofish / cast5 / 3des / tea / xtea / xor / none | `aes` |
| mode | normal / fast / fast2 / fast3 / manual | `fast` |
| mtu | UDP 包最大传输单元 | `1350` |
| sndwnd / rcvwnd | 发送 / 接收窗口大小 | `512` |
| datashard | FEC 数据分片数，常规保持 10 | `10` |
| parityshard | FEC 冗余分片数，0 关闭 FEC | `3` |
| nocomp | 关闭数据压缩（代理套壳流量建议关闭） | `true` |
| tcp | 使用 TCP 传输（开启后以 root 运行） | `false` |
| snmp / pprof | 是否记录 SNMP 日志 / 开启性能监控 | 否 / `false` |

FEC 取值参考：丢包 1%~5% 用 `parityshard 2~3`，5%~10% 用 `4~6`，超过 10% 用 `8~10`；流量开销约为 `(datashard + parityshard) / datashard`。

隐藏参数（acknodelay、sockbuf、smuxbuf、keepalive、smuxver、streambuf）通常保持默认即可。

---

## 丢包测试

脚本内置了基于 KCP OOB（不重传）的丢包测试：客户端按选定速率发送探测包，服务端原样回射，客户端统计**往返丢包率、RTT 分位与抖动**。它直接测量 KCP 会话所走的 UDP 链路，而不是 ICMP，因此能回答“ping/mtr 正常但代理卡顿”这类问题。

### 前提

| 条件 | 说明 |
| --- | --- |
| 版本 | 服务端与 `kcptun-client` 都需要支持 `losstest` 的新版本，且两端版本一致 |
| FEC | 必须开启，`datashard` 与 `parityshard` 都不能为 0 |
| 客户端 | 需要使用 CLI 版客户端，手机端 App 暂不支持 |
| 端口 | 与服务端监听端口相同，无需额外放行 |

### 使用

```sh
sh kcptun.sh losstest [id]
```

也可以在管理菜单选择 `(7) 丢包测试`，按提示完成：

1. 选择测试时长：15 秒 / 30 秒 / 60 秒；
2. 选择发包强度：低度 / 中度 / 全速（适用环境见下表）；
3. 脚本读取当前实例的 key/crypt/mtu/FEC/窗口等参数，生成一条可直接粘贴到**客户端机器**执行的命令；
4. 如果本机存在 `kcptun-client` 二进制，也可以选择本机执行（此时测的是服务器本机到服务端的链路）。

生成的命令示例：

```sh
./kcptun-client -losstest -losstest-duration 15 -losstest-rate mid \
  -remoteaddr '203.0.113.5:29900' -key 'very fast' -crypt aes -mode fast -mtu 1350 \
  -sndwnd 512 -rcvwnd 512 -datashard 10 -parityshard 3 -smuxver 2 ... -nocomp -quiet
```

客户端执行后输出：

```
sent          : 14973 packets
received      : 14852 packets
lost          : 121 packets (0.808%)
rtt           : min 18.20ms / avg 25.40ms / p50 24.00ms / p95 41.00ms / p99 60.00ms / max 120.30ms
jitter        : 3.20ms
```

### 测试步骤

1. 服务端升级到支持 `losstest` 的新版本，保持实例运行（新版本会自动回射探测包，无需改配置）；
2. 确认实例 `datashard` / `parityshard` 均大于 0；
3. 在服务端执行 `sh kcptun.sh losstest`，选时长与强度，复制生成的命令；
4. 在**客户端所在机器**执行该命令（需要同版本 `kcptun-client`）；
5. 根据丢包率、RTT p95 和 jitter 判断线路质量；必要时换档位/时段复测。

### 档位与环境适用性

| 档位 | 速率 | 额外流量 | 适用环境 | 建议时长 |
| --- | --- | --- | --- | --- |
| 低度 | 100 pps | ≈0.1 Mbps | 家用宽带、移动网络、跨境高延迟线路的日常体检；可与业务同时运行 | 60 秒 |
| 中度 | 1000 pps | ≈1 Mbps | 常规 VPS / 家宽，评估日常负载下的线路质量 | 15~30 秒 |
| 全速 | 20000 pps | ≈20 Mbps | 大带宽 VPS、专线、千兆家宽；排查“轻载正常、重载丢包” | 15 秒，避开高峰 |

- 判断是否被 UDP 限速/QoS：同一时段分别跑低、中、全速；低速正常、全速丢包上升，多为带宽或 QoS 限制；三档都丢包则是链路本身问题；
- 观察稳定性：选 60 秒低速，重点看 RTT p95 与 jitter；
- 验证 FEC 调整效果：用同一档位、同一时长做前后对比。

### 结果解读

| 指标 | 参考 |
| --- | --- |
| <0.1% | 优秀 |
| 0.1%~1% | 可用 |
| 1%~3% | 有感知，建议提高 `parityshard`（4~6）并检查线路 |
| >3% | 明显影响体验，优先排查线路、UDP QoS 或拥塞 |
| RTT p95 远高于 min | 存在排队/抖动，关注链路拥塞或 bufferbloat |
| 接近 100% | 检查服务端是否已升级、FEC 是否开启、端口/UDP 是否被拦截 |

### 注意

- 全速档会持续占用约 20 Mbps 带宽，请避免在生产高峰执行；
- 丢包率是**往返合计**（客户端→服务端→客户端），不能单独区分上行/下行；
- 若丢包率接近 100%，优先检查服务端是否已升级、FEC 是否开启；
- 手机端客户端暂不支持该测试。

---

## 文件布局

| 路径 | 说明 |
| --- | --- |
| `/usr/local/kcptun/` | 安装目录（二进制、`bin/jq`、各实例配置） |
| `/usr/local/kcptun/server-config<id>.json` | 实例配置文件 |
| `/var/log/kcptun/server<id>.log` | 实例运行日志 |
| `/var/log/kcptun/snmplog<id>.log` | SNMP 日志（可选） |
| `/etc/systemd/system/kcptun<id>.service` | systemd unit（SysVinit 下为 `/etc/init.d/kcptun<id>`） |

---

## 版本与更新

脚本维护三个独立版本号，定义在 `kcptun.sh` 头部与 `version.json`：

| 版本 | 含义 | 当前值 |
| --- | --- | --- |
| `shell_version` | 安装脚本版本 | `38` |
| `config_version` | 服务端配置格式版本 | `7` |
| `init_version` | 服务文件版本 | `4` |

- `check`：读取 `version.json` 对比版本，只输出结果，不修改文件
- `update`：命令行一次性更新（先更新 Kcptun，再更新安装脚本）
- 启动提示：已安装时运行脚本会对比安装脚本与 Kcptun 的最新版本，**仅提示，不自动更新**；网络不可用时静默跳过
- 更新菜单：主菜单选择 `4` 进入，可分别更新「安装脚本」或「Kcptun」，也可选择全部更新
- 推送 `v*` tag 后，仓库内的 GitHub Actions 会自动创建对应 Release 并附带 `kcptun.sh`

发布新版本：修改版本号 → 更新 `version.json` → 提交 → `git tag -a vXX && git push origin main --tags`。

---

## 从旧版 Supervisor 迁移

```sh
sh kcptun.sh migrate
```

- 仅在存在 `/etc/supervisor/conf.d/kcptun*.conf` 时执行；已是新部署会直接提示无需迁移
- 沿用现有 `server-config<id>.json`，不重新输入参数，迁移期间服务短暂中断
- 旧配置备份到 `/usr/local/kcptun/.legacy-supervisor/`，新服务启动成功后才删除
- 迁移成功后写入 `.supervisor-migrated`（`MIGRATE_VERSION=100`）
- Supervisor 若还托管其他程序会自动跳过卸载，否则询问是否卸载

> 直接运行 `sh kcptun.sh` 时也会自动检测并迁移，不会要求重新配置。

---

## 常见问题

- **端口被占用**：配置监听端口时会检测占用并提示重新输入
- **低端口**：监听端口 ≤ 1024 或开启 TCP 模式时，服务自动以 root 运行
- **防火墙**：自动识别 firewalld / ufw / iptables；已关闭的防火墙不会被启动或重启，失败时输出手动命令
- **下载失败**：设置 `GITHUB_PROXY` 或 `KCPTUN_RELEASES_API` 使用镜像
- **版本回退**：`sh kcptun.sh manual` 输入完整 TAG 即可安装历史版本

---

## 相关链接

- 项目仓库：<https://github.com/TuuzNet/kcptun-script>
- 版本发布：<https://github.com/TuuzNet/kcptun-script/releases>
- 交流群：94537310
