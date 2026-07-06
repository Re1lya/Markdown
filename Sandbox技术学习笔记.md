# Sandbox 技术学习笔记

> 适合对象：刚接触 Sandbox、容器、远程执行环境的新手。  
> 核心问题：如何把一段不完全可信的代码、命令或任务，放到一个受限制的环境里运行，同时控制它能用多少资源、能访问哪些网络、能读写哪些文件。

## 1. Sandbox 是什么

Sandbox（沙箱）是一种隔离执行环境。它的目标不是“让程序跑得更快”，而是把程序的影响范围限制住：

- 程序崩溃时，尽量不影响宿主机或其他任务。
- 程序消耗 CPU、内存、磁盘时，可以被限制。
- 程序访问文件、网络、系统调用时，可以被控制。
- 程序执行完后，环境可以销毁，减少残留状态。

在 coding agent、在线判题、CI、代码解释器、插件运行、数据处理任务里，Sandbox 很常见。比如让 agent 执行用户代码时，不能直接把宿主机文件系统、网络凭据和 Docker socket 暴露给它。

## 2. 先理解三个基础概念

### 2.1 隔离：它能看到什么

Linux 容器常用 namespace 做隔离。可以简单理解为“给进程一副独立眼镜”：

- PID namespace：容器里只能看到自己的进程树。
- Network namespace：容器有自己的网卡、路由和端口空间。
- Mount namespace：容器看到自己的文件系统挂载视图。
- User namespace：容器里的 root 可以映射成宿主机上的普通用户。
- IPC / UTS namespace：隔离进程间通信、hostname 等。

namespace 主要解决“能看到什么、能碰到什么”的问题。

### 2.2 资源限制：它能用多少

cgroups 用来限制和统计资源：

- CPU：限制最多使用多少核或多少 CPU 时间。
- Memory：限制最多使用多少内存，超限可能触发 OOM。
- IO：限制磁盘读写带宽或 IOPS。
- Pids：限制进程数量，防止 fork bomb。

Docker 和 Kubernetes 的 CPU / memory limit，本质上都依赖这类内核能力。

### 2.3 文件系统：它从哪里读写

Sandbox 里的文件通常来自几种方式：

- 镜像层：预装语言运行时、依赖、工具。
- 容器可写层：运行时临时写入，容器删除后通常丢失。
- bind mount：把宿主机某个目录直接挂进容器。
- volume：由容器引擎管理的持久化目录。
- 远程文件系统：例如 NFS、SSHFS、对象存储同步等。

文件挂载是 Sandbox 设计里最容易出安全事故的地方：挂得太多，沙箱就不像沙箱了。

## 3. 本地 Sandbox：Docker 容器

Docker 容器是最常见的本地 Sandbox 方案。它启动快、生态成熟、镜像丰富，适合开发机、CI、单机服务和轻量任务隔离。

### 3.1 基本工作方式

一个容器通常包含：

- 一个镜像：比如 `python:3.13-slim`、`node:22-alpine`。
- 一个入口命令：比如 `python main.py`。
- 一组资源限制：CPU、内存、进程数。
- 一组挂载：代码目录、缓存目录、输出目录。
- 一组网络规则：能不能联网、开放哪些端口。

示例：

```bash
docker run --rm \
  --cpus=1 \
  --memory=512m \
  --pids-limit=128 \
  --network=none \
  --read-only \
  -v "$PWD/work:/workspace:ro" \
  -v "$PWD/out:/out" \
  python:3.13-slim \
  python /workspace/main.py
```

这个例子表达了一个常见思路：

- `--network=none`：禁止网络。
- `--read-only`：容器根文件系统只读。
- `work:/workspace:ro`：输入代码只读挂载。
- `out:/out`：只允许写输出目录。
- `--cpus`、`--memory`、`--pids-limit`：限制资源。

### 3.2 网络

Docker 常见网络模式：

- `bridge`：默认模式，容器接入虚拟网桥，同一网络内容器可通信。
- `none`：关闭网络，适合不需要联网的代码执行沙箱。
- `host`：直接使用宿主机网络，性能好但隔离弱，不适合作为安全沙箱默认选项。
- 自定义 bridge：比默认 bridge 更适合隔离不同任务组，也支持容器名 DNS。

对 Sandbox 来说，默认建议是“能不用网络就不用网络”。如果必须联网，也应限制目标域名、端口和协议。

### 3.3 文件挂载：bind mount 与 volume

bind mount：

- 把宿主机任意路径挂进容器。
- 适合开发调试和把当前项目代码交给容器运行。
- 风险是路径直接来自宿主机，权限、软链接、误挂载都可能扩大访问范围。
- 如果容器可写挂载了宿主机敏感目录，隔离基本失效。

volume：

- 由 Docker 管理，默认位于 Docker 数据目录下。
- 适合持久化缓存、数据库数据、构建缓存。
- 比 bind mount 更抽象、更容易迁移到编排系统。
- 不适合直接编辑宿主机项目源码。

新手记忆方式：

- 要让容器读当前项目源码：多用 bind mount，并尽量只读。
- 要让容器保存内部数据：多用 volume。
- 要做不可信代码沙箱：挂载越少越好，写目录越小越好。

### 3.4 安全边界

Docker 容器共享宿主机内核，所以它不是虚拟机级别的隔离。安全上要注意：

- 不要把 `/var/run/docker.sock` 挂进不可信容器；拿到 Docker socket 通常等于能控制宿主机上的 Docker。
- 避免 `--privileged`。
- 尽量使用非 root 用户运行容器。
- 可启用 user namespace remap，把容器 root 映射为宿主机低权限用户。
- 配合 seccomp、AppArmor、SELinux、capabilities 限制系统调用和 Linux 权限。
- 限制网络、进程数、内存和文件写入范围。

## 4. 本地 Sandbox：Docker Compose

Docker Compose 不是新的隔离技术，它是“多容器编排工具”。它适合把多个容器组成一个本地沙箱环境，例如：

- 一个应用容器。
- 一个数据库容器。
- 一个缓存容器。
- 一个测试执行容器。

示例：

```yaml
services:
  runner:
    image: python:3.13-slim
    command: python /workspace/main.py
    working_dir: /workspace
    network_mode: none
    read_only: true
    pids_limit: 128
    mem_limit: 512m
    cpus: 1
    volumes:
      - ./work:/workspace:ro
      - ./out:/out

  redis:
    image: redis:8-alpine
    networks:
      - sandbox-net

networks:
  sandbox-net: {}
```

Compose 的价值：

- 用一个 `compose.yaml` 固化多容器环境。
- 统一管理服务、网络、volume。
- 更容易复现实验环境。

Compose 的限制：

- 主要适合单机或开发环境。
- 安全边界仍然来自底层 Docker。
- 不适合大规模、多租户、跨机器调度。

## 5. 远端 Sandbox：远程 Docker

远程 Docker 指本地客户端控制远端机器上的 Docker daemon。常见连接方式：

- SSH：例如 `docker -H ssh://user@host ps`。
- TLS over TCP：Docker daemon 监听 TCP 端口，使用双向 TLS 认证。

### 5.1 适合什么场景

- 本地机器性能不足，需要远端大机器跑任务。
- 需要统一使用一台或一组构建机器。
- 想保持 Docker 使用习惯，但把执行位置从本地换到远端。

### 5.2 文件挂载的坑

这是远程 Docker 新手最容易踩的坑：

```bash
docker -H ssh://remote run -v "$PWD:/workspace" image
```

这里的 bind mount 路径是在远端 Docker host 上解析，不是在你的本地电脑上解析。如果远端没有同样的路径，就会失败或挂到错误目录。

常见解决方式：

- 先把代码同步到远端，再用远端路径 bind mount。
- 使用 Git 拉取代码。
- 使用对象存储/制品库传入输入文件和取回输出文件。
- 使用 SSHFS/NFS 把远端或本地目录挂到 Docker host，再让容器 bind mount。
- 构建镜像时把代码打进去，但这会降低迭代速度。

### 5.3 SSHFS 的特点

SSHFS 是基于 FUSE 和 SSH/SFTP 的远程文件系统挂载方式。优点是简单、通用、安全模型容易理解；缺点是性能通常不如本地磁盘或专用分布式文件系统，遇到大量小文件、频繁 stat、依赖安装时会明显变慢。

因此：

- 适合少量文件、配置、结果回传。
- 不适合高频构建缓存、大量依赖目录、数据库数据目录。
- 对 coding agent 场景，更推荐“同步代码到远端本地盘执行”，而不是把整个项目长期跑在 SSHFS 上。

### 5.4 安全边界

远程 Docker 的安全重点是 Docker daemon：

- 不要暴露未加密未认证的 `tcp://host:2375`。
- SSH 方式通常更简单，复用 SSH 身份认证和加密通道。
- TLS 方式适合集成系统调用 Docker API，但证书管理更复杂。
- 能控制远端 Docker daemon 的用户，通常就能获得很高的主机控制能力。

## 6. 远端 Sandbox：Kubernetes Pod

Kubernetes Pod 是 Kubernetes 的最小调度单元。一个 Pod 里可以有一个或多个容器，它们共享网络命名空间和部分存储。

### 6.1 为什么用 Pod 做 Sandbox

Kubernetes 适合多机器、多租户、大规模任务：

- 自动调度到合适节点。
- 配置 CPU / memory request 和 limit。
- 使用 Namespace、RBAC、NetworkPolicy 做权限和网络隔离。
- 使用 PersistentVolume、emptyDir、ConfigMap、Secret 管理存储。
- 任务结束后删除 Pod，回收环境。

### 6.2 Pod 的资源限制

Kubernetes 中常见配置：

- `requests`：调度时需要预留多少资源。
- `limits`：运行时最多允许使用多少资源。

示例：

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "1"
    memory: "1Gi"
```

新手记忆：

- request 决定“能不能被调度到某个节点”。
- limit 决定“最多能用多少”。

### 6.3 Kubernetes 文件挂载方式

常见 volume：

- `emptyDir`：Pod 生命周期内的临时目录，Pod 删除就没了。
- `configMap` / `secret`：挂载配置和密钥。
- `persistentVolumeClaim`：挂载持久卷，适合输出、缓存、共享数据。
- `hostPath`：直接挂宿主机路径，安全风险高，不建议作为通用沙箱方案。

对 Sandbox 来说，优先使用 `emptyDir` 作为临时工作目录，使用 PVC 保存必要产物。谨慎使用 `hostPath`。

### 6.4 安全边界

Kubernetes 默认不是“强隔离多租户安全沙箱”，因为容器仍共享节点内核。要提高安全性，需要组合：

- SecurityContext：非 root、只读根文件系统、禁止 privilege escalation、丢弃 Linux capabilities。
- Pod Security Standards：限制特权容器、host namespace、危险能力。
- NetworkPolicy：限制 Pod 入站/出站网络。
- RBAC：限制 Pod 能访问的 Kubernetes API。
- RuntimeClass：接入 gVisor、Kata Containers、Firecracker 等更强隔离运行时。

## 7. 远端 Sandbox：Firecracker microVM

Firecracker 是轻量虚拟化技术，用 KVM 创建 microVM。它常被用于 serverless、函数计算、多租户容器隔离等场景。

### 7.1 它和容器有什么不同

容器：

- 共享宿主机内核。
- 启动快，资源开销低。
- 隔离主要靠 namespace、cgroups、seccomp 等。

Firecracker microVM：

- 每个 microVM 有独立 guest kernel。
- 隔离边界更接近虚拟机。
- 设备模型极简，启动速度和资源开销接近容器。
- 运维复杂度高于 Docker 容器。

### 7.2 为什么安全性更强

容器逃逸的关键风险之一是共享宿主机内核。microVM 给每个 workload 一个独立内核，并通过 KVM 做硬件虚拟化隔离，攻击面更小。Firecracker 还强调极简设备模型，以减少不必要的虚拟设备和 guest-facing 功能。

但注意：更强隔离不等于“绝对安全”。你仍然要处理：

- 镜像/rootfs 构建。
- 网络隔离。
- 文件注入和结果回收。
- API 权限。
- microVM 生命周期管理。
- 宿主机 KVM、内核、jailer 等组件安全。

### 7.3 文件系统和启动

Firecracker 常见输入包括：

- kernel image。
- rootfs 镜像。
- 通过 block device、virtio、网络或预构建 rootfs 注入文件。

和 Docker bind mount 相比，microVM 的文件共享没有那么自然。它更适合“任务开始前准备 rootfs/输入，任务结束后取回结果”的模式。

## 8. 关键维度对比

### 8.1 启动速度

大致排序：

1. 已有容器复用 / warm container：最快。
2. Docker 容器：通常很快，镜像已存在时可在秒级甚至更低。
3. Firecracker microVM：比传统 VM 快很多，目标是接近容器级启动体验。
4. Kubernetes Pod：实际启动时间取决于调度、拉镜像、CNI、存储挂载，可能从几秒到几十秒。
5. 传统 VM：通常最慢，不是本文重点。

### 8.2 文件挂载

- 本地 Docker：bind mount 最方便，volume 适合持久化。
- Docker Compose：本质同 Docker，但更适合声明多个服务的挂载。
- 远程 Docker：bind mount 指向远端路径；本地文件要先同步或用远程文件系统。
- Kubernetes Pod：用 emptyDir、PVC、ConfigMap、Secret；hostPath 风险高。
- Firecracker：更偏 rootfs / block device / 任务输入输出，不像 Docker 那样直接挂宿主机目录。

### 8.3 安全边界

从弱到强的大致理解：

- Docker/Compose：进程级隔离，共享宿主机内核；适合可信或半可信任务，需加固。
- 远程 Docker：隔离强度仍是 Docker，但多了远端 daemon 暴露风险。
- Kubernetes Pod：容器隔离 + 集群治理能力；强弱取决于安全配置和运行时。
- Firecracker microVM：虚拟机级边界更强，适合多租户和不可信任务，但复杂度更高。

## 9. 面向 coding agent 的推荐选型

### 9.1 本地开发和个人工具

推荐：Docker 或 Docker Compose。

原因：

- 上手快。
- 镜像生态好。
- 方便挂载当前项目。
- 资源限制和网络关闭都容易配置。

建议：

- 默认只读挂载项目源码。
- 单独挂载输出目录。
- 默认禁用网络。
- 不挂 Docker socket。
- 设置 CPU、内存、进程数限制。

### 9.2 团队内部远程执行

推荐：远程 Docker 或 Kubernetes Job/Pod。

选择远程 Docker：

- 团队规模小。
- 想保持 Docker 使用方式。
- 可接受自己管理机器和同步代码。

选择 Kubernetes：

- 已有集群。
- 需要并发调度、多租户、配额、审计、网络策略。
- 需要更标准的运维治理。

### 9.3 多租户、不可信代码执行

推荐：Kubernetes + 强隔离运行时，或 Firecracker microVM。

原因：

- 不可信代码可能尝试逃逸、扫描网络、消耗资源、窃取挂载文件。
- 单纯 Docker 需要非常谨慎的加固。
- microVM 能提供更清晰的内核隔离边界。

### 9.4 一个实用分层架构

```text
Agent / 调度器
  |
  |-- 本地快速任务：Docker container
  |-- 多服务集成测试：Docker Compose
  |-- 远端大资源任务：Remote Docker / Kubernetes Job
  |-- 高风险不可信任务：Firecracker microVM / Kubernetes 强隔离 Runtime
```

## 10. 新手检查清单

设计 Sandbox 时，至少问自己 10 个问题：

1. 任务是否可信？是否来自用户输入或外部代码？
2. 是否需要网络？如果需要，能否限制目标？
3. 容器是否必须 root？能否用非 root？
4. 是否设置 CPU、内存、进程数限制？
5. 输入目录是否只读？
6. 输出目录是否最小化？
7. 是否挂载了 Docker socket、宿主机根目录、SSH key、云厂商凭据？
8. 是否需要持久化？用 bind mount、volume、PVC，还是对象存储？
9. 任务失败或超时后，资源能否自动清理？
10. 日志、产物、错误信息是否会泄露敏感数据？

## 11. 方案一句话总结

- Docker：本地最快上手的沙箱，适合开发和轻量隔离。
- Docker Compose：多容器本地环境编排，不是更强沙箱。
- 远程 Docker：把 Docker 执行搬到远端，重点处理 daemon 安全和文件同步。
- Kubernetes Pod：适合规模化、远端、多租户调度，安全性取决于配置。
- Firecracker microVM：更强隔离边界，适合高风险任务，但工程复杂度更高。

## 参考资料

- [Docker: Resource constraints](https://docs.docker.com/engine/containers/resource_constraints/)
- [Docker: Bind mounts](https://docs.docker.com/engine/storage/bind-mounts/)
- [Docker: Volumes](https://docs.docker.com/engine/storage/volumes/)
- [Docker: Networking overview](https://docs.docker.com/engine/network/)
- [Docker: Bridge network driver](https://docs.docker.com/engine/network/drivers/bridge/)
- [Docker: Configure remote access for Docker daemon](https://docs.docker.com/engine/daemon/remote-access/)
- [Docker: Protect the Docker daemon socket](https://docs.docker.com/engine/security/protect-access/)
- [Docker: User namespace remap](https://docs.docker.com/engine/security/userns-remap/)
- [Docker Compose file reference](https://docs.docker.com/reference/compose-file/)
- [Kubernetes: Pods](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Kubernetes: Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Kubernetes: Volumes](https://kubernetes.io/docs/concepts/storage/volumes/)
- [Kubernetes: Configure a Security Context for a Pod or Container](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Firecracker official site](https://firecracker-microvm.github.io/)
- [Firecracker GitHub repository](https://github.com/firecracker-microvm/firecracker)
- [Firecracker NSDI paper](https://www.usenix.org/system/files/nsdi20-paper-agache.pdf)
- [Red Hat: SSHFS remote file system](https://www.redhat.com/en/blog/sshfs)
