# kcptun-script

> Kcptun 服务端一键安装与管理脚本 · 当前版本 **v31**

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

### 环境要求

- 系统：Ubuntu / Debian / Raspbian / CentOS / Fedora / RedHat / OracleLinux / Photon
- 架构：x86_64（amd64）、x86（386）、arm64、arm
- 权限：root
- 服务管理：systemd（优先）或 SysVinit

### 安装

```sh
wget --no-check-certificate -O kcptun.sh https://github.com/TuuzNet/kcptun-script/raw/main/kcptun.sh
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
| `shell_version` | 安装脚本版本 | `31` |
| `config_version` | 服务端配置格式版本 | `7` |
| `init_version` | 服务文件版本 | `4` |

- `check`：读取 `version.json` 对比版本，只输出结果，不修改文件
- `update`：脚本更新先下载到临时文件并通过 `shell_sha256` 校验，失败不会破坏当前脚本
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
