---
title: POC部署问题与解决方案记录
type: troubleshooting-record
project: 平台工程 POC / 华为上研所实习
created: 2026-07-16
updated: 2026-07-16
tags:
  - 故障排查
  - Kubernetes
  - Helm
  - ArgoCD
  - Tekton
  - Backstage
  - GitOps
---

# POC 部署问题与解决方案记录

## 1. 文档目的

本文记录平台工程 POC 在迁移到服务器、重新部署、镜像加速、CI/CD 调试、Backstage 访问等过程中遇到的问题和解决方案。

排序原则：

```text
优先级 = 问题难度 + 出现次数 + 对部署链路影响程度
```

越靠前的问题，越建议优先沉淀为排障 SOP。

## 2. 问题总览

| 排名 | 问题 | 难度 | 出现频率 | 影响范围 |
| --- | --- | --- | --- | --- |
| 1 | Helm、Argo CD、kubectl patch 多方管理同一资源导致冲突 | 高 | 多次 | Tekton、AppService、Argo CD Application |
| 2 | 镜像拉取超时、ImagePullBackOff、代理镜像不生效 | 高 | 多次 | Crossplane、Tekton、Backstage、Envoy Gateway |
| 3 | GitHub Webhook + Tunnel 到 Tekton EventListener 链路不稳定 | 高 | 多次 | CI/CD 自动触发 |
| 4 | Tekton 手动 curl 能触发，但 GitHub push 不生成 PipelineRun | 高 | 多次 | CI 触发入口 |
| 5 | kind 集群镜像已 load 但 Pod 仍重新拉取 | 中高 | 多次 | Tekton、Backstage、Envoy |
| 6 | Argo CD Helm Release 安装卡住或 timeout | 中高 | 多次 | GitOps CD |
| 7 | Envoy Gateway chart 和 data plane 镜像地址覆盖不完整 | 中高 | 多次 | Demo 服务访问 |
| 8 | Backstage 镜像和 PostgreSQL 镜像拉取失败 | 中 | 多次 | Dev Portal |
| 9 | Tekton Trigger CRD 未安装完成就 apply ClusterInterceptor | 中 | 多次 | EventListener / Interceptor |
| 10 | Secret、GitHub token、Webhook secret 配置理解不清 | 中 | 多次 | CI/CD、Webhook |
| 11 | SSH、本机端口、服务器端口、port-forward、tunnel 混淆 | 中 | 多次 | 页面访问与 Webhook 调试 |
| 12 | 手动 curl 使用假的 commit sha 导致 clone checkout 失败 | 中 | 一次以上 | Pipeline clone task |
| 13 | Backstage Catalog Open Service 链接仍指向 localhost | 低中 | 一次以上 | 服务访问 |
| 14 | GitHub Desktop bad object refs/codex 导致 fetch 异常 | 低中 | 一次 | 本地 Git 操作 |
| 15 | nano / Linux 基础操作不熟悉 | 低 | 多次 | 操作效率 |
| 16 | Helm repo 不可达或 chart 下载慢 | 中 | 多次 | Argo CD、Envoy Gateway、Backstage |
| 17 | Helm release 处于 pending upgrade，导致 another operation is in progress | 中 | 一次以上 | Helm 升级与重装 |
| 18 | HTTP_PROXY / NO_PROXY 设置不当影响集群内访问 | 中 | 一次以上 | 镜像拉取、Pod 访问、本地调试 |
| 19 | 混淆 Helm chart 下载和容器镜像拉取 | 中 | 多次 | 安装判断与排障方向 |

## 3. 问题 1：Helm、Argo CD、kubectl patch 多方管理同一资源导致冲突

### 现象

安装或升级 Helm chart 时出现类似错误：

```text
Error: unable to continue with install: Namespace "ci" exists and cannot be imported into the current release:
invalid ownership metadata
missing key "app.kubernetes.io/managed-by": must be set to "Helm"
missing key "meta.helm.sh/release-name": must be set to "platform-tekton"
missing key "meta.helm.sh/release-namespace": must be set to "ci"
```

也出现过：

```text
conflict with "argocd-controller" using tekton.dev/v1: .spec.tasks
conflict with "argocd-controller" using triggers.tekton.dev/v1beta1: .spec.triggers
```

以及：

```text
conflict with "kubectl-patch" using argoproj.io/v1alpha1: .spec.source.path
```

### 根本原因

同一个 Kubernetes 资源被多个控制方管理：

- Helm 想管理 `ci` namespace、Secret、Tekton Task、Pipeline、EventListener。
- Argo CD 也在同步同一批 Tekton 或 AppService 资源。
- 手动 `kubectl patch` 又修改了 Argo CD Application 的字段。

Kubernetes server-side apply 会记录 field manager。当不同 manager 修改同一字段时，就会出现冲突。

### 解决方案

核心原则：

```text
一个资源只能有一个主要管理方。
```

建议划分：

- 平台组件安装：Helm 管理。
- GitOps 应用资源：Argo CD 管理。
- 临时排障 patch：只用于验证，验证后要回写到 Helm chart 或 GitOps 仓库。

常用处理方式：

```bash
# 查看资源由谁管理
kubectl -n ci get task clone-repo -o yaml | grep -n "managedFields" -A40

# 停止 Argo CD 对某个 Application 的自动同步
kubectl -n argocd patch application platform-ci --type merge \
  -p '{"spec":{"syncPolicy":null}}'

# 删除冲突的旧资源，让当前管理方重新创建
kubectl -n ci delete secret github-webhook-secret
kubectl -n default delete appservice fastapi-demo-2
```

### 经验教训

不要频繁在 Helm、Argo CD、kubectl patch 之间切换管理同一份 YAML。临时 patch 成功后，必须把修改固化回 chart 或 GitOps 文件。

## 4. 问题 2：镜像拉取超时、ImagePullBackOff、代理镜像不生效

### 现象

Pod 长时间处于：

```text
ContainerCreating
Pulling
ErrImagePull
ImagePullBackOff
```

典型错误：

```text
failed to resolve reference "docker.io/envoyproxy/gateway:v1.8.2"
dial tcp ... i/o timeout
```

```text
failed to pull image "docker.io/bitnamilegacy/postgresql:15.4.0-debian-11-r10"
```

```text
failed to pull image "ghcr.io/backstage/backstage:latest"
```

### 根本原因

服务器访问 DockerHub、GHCR、ECR、Quay 等外部镜像仓库速度慢或超时。即使宿主机能拉到镜像，kind 集群节点也不一定有该镜像。

### 解决方案

优先级从高到低：

1. 修改 Helm values 或 YAML，让 Pod 直接使用代理镜像地址。
2. 在宿主机提前 `docker pull`，再 `kind load docker-image` 到指定 kind 集群。
3. 本地拉取后 `docker save` 成 tar，用 `rsync` 传服务器，再 `docker load`。
4. 延长 Helm / install 脚本 timeout，例如 40m。

常用命令：

```bash
# 查看 Pod 正在拉哪个镜像
kubectl -n <namespace> describe pod <pod-name> | grep -A5 -B5 "Pulling image"

# 查看 Deployment 当前镜像
kubectl -n <namespace> get deploy <deploy-name> -o jsonpath='{..image}'

# kind 加载镜像到指定集群
kind load docker-image <image>:<tag> --name platform-poc-2
```

### 注意事项

镜像名必须完全一致。例如 Pod 里写的是：

```text
docker.io/envoyproxy/envoy:distroless-v1.38.3
```

只 load：

```text
envoyproxy/envoy:distroless-v1.38.3
```

可能仍导致 Kubernetes 去远端拉取。需要保证 registry、repository、tag 对齐。

## 5. 问题 3：GitHub Webhook + Tunnel 到 Tekton EventListener 链路不稳定

### 现象

GitHub Webhook 页面显示 202，port-forward 也显示：

```text
Handling connection for 8080
```

但：

- EventListener Pod 没有明显日志。
- 没有新的 PipelineRun。
- 本机监听脚本没有打印 GitHub 请求内容。

### 根本原因

`Handling connection` 只能说明 TCP 连接到了 port-forward，不代表 EventListener 应用层成功处理了请求。

同时，本机 8080 端口可能被 SSH 占用，导致 Python dump proxy 根本没有监听到请求。

错误链路可能是：

```text
GitHub -> cloudflared -> 本机 8080 SSH tunnel -> 服务器 port-forward
```

而预期调试链路应该是：

```text
GitHub
  -> cloudflared
  -> 本机 127.0.0.1:8080 Python dump proxy
  -> 本机 127.0.0.1:18080 SSH tunnel
  -> 服务器 127.0.0.1:8080 kubectl port-forward
  -> Tekton EventListener
```

### 解决方案

检查端口：

```bash
ss -lntp | grep -E ':8080|:18080'
```

正确状态应该是：

```text
127.0.0.1:8080   python3
127.0.0.1:18080  ssh
```

重新建立链路：

```bash
# 服务器
kubectl -n ci port-forward svc/el-fastapi-demo-2-ci-listener 8080:8080

# 本机
ssh -L 18080:127.0.0.1:8080 admin@服务器地址

# 本机
cloudflared tunnel --url http://127.0.0.1:8080
```

### 经验教训

排 Webhook 时必须抓真实请求，而不是只看 GitHub 的 202 或 port-forward 的 Handling。

## 6. 问题 4：Tekton 手动 curl 能触发，但 GitHub push 不生成 PipelineRun

### 现象

手动 curl EventListener 可以生成 PipelineRun，但 GitHub push 后没有新的 PipelineRun。

GitHub 返回类似：

```json
{"eventListener":"fastapi-demo-2-ci-listener","namespace":"ci","eventID":"..."}
```

但 `kubectl -n ci get pipelinerun` 没有新增。

### 可能原因

- GitHub 请求 header 和手动 curl 不一致。
- `X-GitHub-Event` 不是 `push`。
- Webhook secret 签名不匹配。
- CEL filter 拦截。
- 监控的是旧 PipelineRun，`watch-fastapi-demo-ci.ps1 -WaitForNew` 只看脚本启动后的新资源。
- 请求到了 EventListener，但 TriggerTemplate 创建资源失败。

### 排查命令

```bash
kubectl -n ci logs pod/<eventlistener-pod> --all-containers=true --since=10m
kubectl -n ci get pipelinerun --sort-by=.metadata.creationTimestamp
kubectl -n ci get triggerbinding,triggertemplate,pipeline,task
kubectl auth can-i create pipelineruns.tekton.dev \
  --as=system:serviceaccount:ci:fastapi-demo-2 \
  -n ci
```

### 稳定替代方案

临时接入或排障时可以绕过 GitHub Webhook 和 tunnel：

```text
手动 curl -> Tekton PipelineRun -> GitOps 更新 -> Argo CD 同步
```

或者使用包装脚本：

```bash
git push origin main && ./trigger-tekton.sh
```

## 7. 问题 5：kind 集群镜像已 load 但 Pod 仍重新拉取

### 现象

已经执行：

```bash
kind load docker-image <image>:<tag> --name platform-poc-2
```

但 Pod 仍然显示：

```text
Pulling image ...
```

### 根本原因

常见原因：

- load 到了错误的 kind 集群。
- 镜像 tag 不完全一致。
- Pod 声明的镜像带 registry，宿主机镜像不带 registry。
- `imagePullPolicy: Always` 导致每次都尝试远端拉取。
- 多节点 kind 集群中镜像没有正确导入所有节点。
- tar 或多架构镜像导入时出现 digest 缺失。

### 解决方案

确认集群名：

```bash
kind get clusters
kubectl config current-context
```

确认 Pod 镜像：

```bash
kubectl -n <namespace> get pod <pod> -o jsonpath='{..image}'
```

必要时重新 tag：

```bash
docker tag 原镜像:tag 目标镜像:tag
kind load docker-image 目标镜像:tag --name platform-poc-2
```

同时尽量设置：

```yaml
imagePullPolicy: IfNotPresent
```

## 8. 问题 6：Argo CD Helm Release 安装卡住或 timeout

### 现象

安装脚本卡在：

```text
release.helm.m.crossplane.io/argocd created
```

或：

```text
argocd configured
```

Argo CD Pod 长时间拉镜像，例如 Redis 镜像拉了二十多分钟。

### 根本原因

Crossplane provider-helm 安装 Helm chart 时受网络和镜像拉取影响。Helm chart 本身可能已下载，但 Pod 镜像仍需从远端拉取。

### 解决方案

可以改为手动安装本地 tgz：

```bash
kubectl -n default delete release.helm.m.crossplane.io argocd --ignore-not-found

helm upgrade --install argocd /home/admin/argo-cd-10.1.2.tgz \
  -n argocd \
  --create-namespace \
  --set crds.install=true \
  --set crds.keep=true \
  --set dex.enabled=false \
  --set server.extraArgs="{--insecure}" \
  --set configs.params.server\\.insecure=true \
  --wait \
  --timeout 40m
```

### 经验教训

手动安装 Helm chart 只能绕过 chart 下载问题，不能绕过镜像拉取问题。镜像仍需要代理、预拉取或 load。

## 9. 问题 7：Envoy Gateway chart 和 data plane 镜像地址覆盖不完整

### 现象

已经给 Helm 设置：

```bash
--set image.registry=dockerproxy.net
--set image.repository=envoyproxy/gateway
```

但 Pod 仍然拉：

```text
docker.io/envoyproxy/gateway:v1.8.2
docker.io/envoyproxy/envoy:distroless-v1.38.3
```

### 根本原因

Envoy Gateway chart 的 values 不是简单的 `image.registry/image.repository`。它可能使用：

```yaml
global:
  images:
    envoyGateway:
      image: docker.io/envoyproxy/gateway:v1.8.2
```

同时 data plane 的 Envoy 镜像由 `EnvoyProxy` 资源控制，不一定由 Helm chart 顶层 image 参数控制。

### 解决方案

查看 chart values：

```bash
helm show values /home/admin/gateway-helm-v1.8.2.tgz | grep -n -E "image|registry|repository|tag|pullPolicy|certgen"
```

对于 data plane，需要修改 Gateway 相关 YAML 中的 EnvoyProxy 配置，例如：

```yaml
envoyDeployment:
  container:
    image: dockerproxy.net/envoyproxy/envoy:distroless-v1.38.3
```

然后升级 chart 或重新 apply 管理该资源。

## 10. 问题 8：Backstage 镜像和 PostgreSQL 镜像拉取失败

### 现象

Backstage Pod 拉取：

```text
platform-poc-backstage:0.1.5
```

结果 Kubernetes 解释成：

```text
docker.io/library/platform-poc-backstage:0.1.5
```

PostgreSQL 拉取：

```text
docker.io/bitnamilegacy/postgresql:15.4.0-debian-11-r10
```

出现 timeout。

### 根本原因

Backstage image 没写 registry 和 repository，导致默认走 DockerHub library。PostgreSQL 仍使用 DockerHub 源地址，服务器拉取慢。

### 解决方案

在 `backstage-values.yaml` 中明确写：

```yaml
backstage:
  image:
    registry: ghcr.io
    repository: re1lya/platform-poc-backstage
    tag: "0.1.5"
    pullPolicy: IfNotPresent

postgresql:
  enabled: true
  image:
    registry: dockerproxy.net
    repository: bitnamilegacy/postgresql
    tag: 15.4.0-debian-11-r10
    pullPolicy: IfNotPresent
```

如果使用 GHCR 代理，可把 registry 改为可用的代理域名，但需要先验证该代理是否能拉取。

## 11. 问题 9：Tekton Trigger CRD 未安装完成就 apply ClusterInterceptor

### 现象

应用 interceptors.yaml 时出现：

```text
resource mapping not found for name: "github" namespace: "" from "interceptors.yaml":
no matches for kind "ClusterInterceptor" in version "triggers.tekton.dev/v1alpha1"
ensure CRDs are installed first
```

执行：

```bash
kubectl get crd | grep -i interceptor
```

没有输出。

### 根本原因

Tekton Triggers 的 CRD 还没安装成功，或者 install 脚本引用了错误的 release YAML。

### 解决方案

先确认 Tekton Pipeline 和 Triggers release 分别使用正确 YAML：

```bash
kubectl apply -f tekton-pipeline-release.yaml
kubectl apply -f tekton-triggers-release.yaml
```

等待 CRD 出现：

```bash
kubectl get crd | grep -i interceptor
```

再 apply interceptors：

```bash
kubectl apply -f interceptors.yaml
```

### 经验教训

CRD 类资源安装必须等 CRD ready 后再 apply CR，否则 Kubernetes 不认识对应 kind。

## 12. 问题 10：Secret、GitHub token、Webhook secret 配置理解不清

### 现象

用户不确定：

- `GITHUB_TOKEN` 是什么。
- `GITHUB_WEBHOOK_SECRET` 是什么。
- GitHub Webhook 页面里的 Secret 是否要和集群一致。
- GHCR 是否需要登录。

### 解释

`GITHUB_TOKEN` 用于 Tekton 或脚本访问 GitHub，例如 clone 私有仓库、push GitOps 修改。

`GITHUB_WEBHOOK_SECRET` 用于 GitHub Webhook 签名校验。GitHub 发送请求时会用这个 secret 计算签名，Tekton GitHub interceptor 用集群 Secret 中的同一个值验证请求是否可信。

两边必须一致：

```text
GitHub Webhook Secret == Kubernetes Secret github-webhook-secret 中的 secretToken
```

### 验证命令

```bash
kubectl -n ci get secret github-webhook-secret -o yaml
```

不要把真实 token 或 secret 写入文档，应使用：

```text
<REDACTED>
```

## 13. 问题 11：SSH、本机端口、服务器端口、port-forward、tunnel 混淆

### 现象

不清楚：

- SSH 是不是让两边 8080 互通。
- `localhost` 到底是本机还是服务器。
- cloudflared 应该连哪个端口。
- 8080、18080、7007、30080 分别是什么。

### 正确理解

SSH `-L` 是本机监听一个端口，再转发到服务器能访问的地址和端口。

示例：

```bash
ssh -L 18080:127.0.0.1:8080 admin@服务器地址
```

含义：

```text
本机 127.0.0.1:18080
  -> SSH
  -> 服务器 127.0.0.1:8080
```

Backstage：

```bash
kubectl -n backstage port-forward svc/backstage 7007:7007
ssh -L 7007:127.0.0.1:7007 admin@服务器地址
```

Demo 服务：

```bash
ssh -L 30080:127.0.0.1:30080 admin@服务器地址
```

## 14. 问题 12：手动 curl 使用假的 commit sha 导致 clone checkout 失败

### 现象

Tekton clone step 报错：

```text
cloning into 'repo'
error: pathspec 'manual-trigge-20260175' did not match any files known to git
```

### 根本原因

手动 curl 的 payload 里使用了假的 commit id：

```json
"after": "manual-trigger-20260715"
```

Tekton clone task 会尝试：

```bash
git checkout <commit_sha>
```

但这个 commit 在 Git 仓库中不存在。

### 解决方案

手动触发时使用真实 commit sha：

```bash
COMMIT_SHA="$(git rev-parse HEAD)"
```

payload 中：

```json
"head_commit": {
  "id": "<真实 commit sha>"
},
"after": "<真实 commit sha>"
```

## 15. 问题 13：Backstage Catalog Open Service 链接仍指向 localhost

### 现象

Backstage 中点击 `Open Service` 打开的仍是：

```text
http://localhost:30080/
```

但希望浏览器直接访问：

```text
http://110.120.0.3:30080/
```

### 根本原因

`Open Service` 是 Backstage Catalog entity 的 `links`，不是 Kubernetes Service 或 Helm values。

### 解决方案

修改：

```text
crossplane-backstage-poc/catalog/services/fastapi-demo-2/catalog-info.yaml
```

把：

```yaml
- url: http://localhost:30080/
  title: Open Service
```

改成：

```yaml
- url: http://110.120.0.3:30080/
  title: Open Service
```

提交并推送到 GitHub 后，Backstage GitHub catalog provider 会在刷新后读取新值。

## 16. 问题 14：GitHub Desktop bad object refs/codex 导致 fetch 异常

### 现象

GitHub Desktop 报错：

```text
fatal: bad object refs/codex/turn-diffs/captures/.../base
error: https://github.com/Re1lya/Markdown.git did not send all necessary objects
```

### 根本原因

本地 `.git/refs/codex/...` 下存在损坏的 Codex 临时 ref。

### 解决方案

删除损坏 ref 文件后重新 fetch：

```powershell
Remove-Item "D:\Markdown\.git\refs\codex\turn-diffs\captures\...\base" -Force
git fetch origin --prune
```

### 注意事项

只删除确认损坏的 Codex 临时 ref，不要执行 `git reset --hard` 或删除正常业务分支。

## 17. 问题 15：Linux / nano / rsync 等基础操作

### 常见问题

- nano 输入错误后如何撤回。
- nano 如何粘贴。
- Linux 如何移动文件。
- rsync 如何传 tar 文件。
- tar 镜像如何 docker load。

### 常用命令

```bash
# 移动文件
mv 源文件 目标路径

# rsync 传文件
rsync -avP 本地文件.tar admin@服务器地址:/home/admin/

# 加载 Docker 镜像 tar
docker load -i image.tar

# 保存 Docker 镜像
docker save 镜像名:tag -o image.tar
```

### 注意事项

`docker save` 必须带 `-o` 输出文件，否则会把 tar 内容输出到终端，出现：

```text
cowardly refusing to save to a terminal
```

## 18. 问题 16：Helm repo 不可达或 chart 下载慢

### 现象

安装平台组件时出现类似：

```text
argoproj.github.io/argo-helm is not a valid chart repository or cannot be reached
```

或者 Helm install / upgrade 卡在拉取 chart 阶段。

### 根本原因

服务器访问 Helm chart repository 不稳定，或者 Helm repo 缓存中存在旧索引、损坏索引。这个问题和 Pod 镜像拉取是两件事：

```text
Helm chart 下载失败：Helm 拿不到安装包
镜像拉取失败：Kubernetes Pod 拿不到容器镜像
```

### 解决方案

可以先更新 repo：

```bash
helm repo update
```

如果 repo 缓存损坏，可以清理 Helm repo 缓存后重新添加。执行清理前需要确认路径，避免误删其他目录：

```bash
echo "$HELM_REPO_DIR"
rm -rf "$HELM_REPO_DIR"
```

更稳的做法是：在网络较好的机器上先下载 chart tgz，再传到服务器：

```bash
helm pull argo/argo-cd --version 10.1.2
rsync -avP argo-cd-10.1.2.tgz admin@服务器地址:/home/admin/
```

服务器上用本地 tgz 安装：

```bash
helm upgrade --install argocd /home/admin/argo-cd-10.1.2.tgz \
  -n argocd \
  --create-namespace \
  --wait \
  --timeout 40m
```

### 经验教训

本地 tgz 只能解决 chart 获取问题，不能解决 chart 里声明的容器镜像拉取问题。安装卡住时，要区分是 Helm 还在下载 chart，还是 Kubernetes 已经创建 Pod 但 Pod 在拉镜像。

## 19. 问题 17：Helm release 处于 pending upgrade

### 现象

执行 Helm 升级时出现：

```text
another operation is in progress
```

或者：

```text
STATUS: pending-upgrade
```

### 根本原因

上一次 Helm install / upgrade 没有正常结束，release 状态停留在 pending。Helm 为了避免并发修改同一个 release，会拒绝新的操作。

### 排查命令

```bash
helm list -A
helm history <release-name> -n <namespace>
```

### 解决方案

如果存在上一个成功版本，可以回滚：

```bash
helm rollback <release-name> <revision> -n <namespace>
```

如果没有可用版本，且确认该 release 是 POC 环境中可重建组件，可以卸载后重装：

```bash
helm uninstall <release-name> -n <namespace>
helm upgrade --install <release-name> <chart-or-tgz> -n <namespace> --wait --timeout 40m
```

### 注意事项

生产环境不能直接用卸载重装替代回滚。POC 环境可以这样处理，但执行前仍要确认 release 管理的是平台组件还是业务资源。

## 20. 问题 18：HTTP_PROXY / NO_PROXY 设置不当影响访问

### 现象

设置代理后，某些外部镜像拉取变快，但集群内、本机或 localhost 访问出现异常。例如：

- 原本能访问的本地端口突然不通。
- Pod 或脚本访问 `127.0.0.1`、Kubernetes service、内网地址时绕到代理。
- 设置 `NO_PROXY` 后镜像拉取行为变化。

### 根本原因

`HTTP_PROXY` / `HTTPS_PROXY` 会影响命令行工具访问网络。`NO_PROXY` 用于告诉工具哪些地址不要走代理。若 `NO_PROXY` 太少，本地和集群内地址可能被错误代理；若代理变量没有传到 Docker/containerd/kubelet，则 Pod 拉镜像仍不会走代理。

### 建议配置

常见 POC 配置示例：

```bash
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export NO_PROXY=127.0.0.1,localhost,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.svc,.cluster.local
```

### 注意事项

Shell 里的代理变量不一定会自动影响 kind 节点里的 containerd。Pod 镜像拉取问题通常要从以下方向处理：

- 修改镜像地址为代理仓库。
- 配置 Docker/containerd 代理。
- 预拉取并 `kind load docker-image`。
- 使用内网镜像仓库。

## 21. 问题 19：混淆 Helm chart 下载和容器镜像拉取

### 现象

已经把 chart tgz 上传到服务器并执行本地安装，但安装仍然卡住，K9s 里看到 Pod 继续从 DockerHub、GHCR 或 ECR 拉镜像。

### 根本原因

Helm chart 是 Kubernetes 资源模板包；容器镜像是 Pod 真正运行的应用文件系统。两者不是同一个东西。

```text
helm install xxx.tgz
  -> 渲染 Deployment / Service / Job 等资源
  -> Kubernetes 根据 Deployment 里的 image 字段拉容器镜像
```

所以本地安装 chart 只说明 Helm 不需要再联网下载 chart，不代表 Pod 不需要联网拉镜像。

### 解决方案

分开排查：

```bash
# Helm release 是否安装
helm list -A

# Pod 是否因为镜像失败
kubectl get pods -A | grep -E 'ImagePullBackOff|ErrImagePull|ContainerCreating'

# Pod 实际拉取的镜像
kubectl -n <namespace> describe pod <pod-name> | grep -A5 -B5 "image"
```

如果是镜像问题，按本文“镜像拉取超时、ImagePullBackOff、代理镜像不生效”处理。

## 22. 推荐稳定接入策略

为了保证服务接入流程可重复、可排查，建议优先使用稳定路径：

```text
1. 手动 curl 或包装脚本触发 Tekton
2. 避免临时 tunnel 作为关键链路
3. 提前 load 或代理所有关键镜像
4. Helm 与 Argo CD 管理边界固定
5. Backstage 只作为 Dev Portal 展示入口
6. Argo CD 只展示 GitOps 同步状态
```

## 23. 后续需要补充的信息

以下内容当前仍建议后续补充：

- 服务器最终可用的公网 IP 或域名是否固定。
- GitHub Webhook 最终是否继续使用 tunnel。
- 是否存在企业内部镜像仓库可替代 dockerproxy。
- Helm chart 最终拆分结构和安装顺序是否已经固化。
- 每个 chart 的 values 是否已经收敛成服务器环境专用 values 文件。
- Argo CD 与 Helm 管理资源边界是否已写成明确文档。
- CI/CD 成功反馈脚本是否最终保留。
