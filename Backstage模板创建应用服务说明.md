---
title: Backstage模板创建应用服务说明
type: platform-usage-guide
project: 平台工程 POC / 华为上研所实习
created: 2026-07-16
updated: 2026-07-16
tags:
  - Backstage
  - Software-Templates
  - Kubernetes
  - Tekton
  - ArgoCD
  - GitOps
---

# Backstage 模板创建应用服务说明

## 1. 文档目的

本文说明如何使用 Backstage 上的 Software Templates，把一个已有应用服务接入当前平台，并最终部署到 Kubernetes 集群。

同时说明：

- 当前模板适合什么服务。
- 模板会生成哪些文件。
- 生成后 Tekton、Argo CD、Crossplane、Backstage Catalog 分别做什么。
- 如果新服务不符合当前模板，应该如何扩展模板或新建模板。

本文面向两类场景：

- 服务接入：说明如何填写模板、查看 PR、确认服务是否进入平台。
- 平台维护：说明模板如何接入 Tekton、Argo CD、Crossplane 和 Kubernetes，以及模板不适用时如何扩展。

## 2. 当前模板定位

当前 POC 中已有的核心模板是：

```text
register-existing-fastapi-service
```

模板文件位置：

```text
crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-fastapi/template.yaml
```

它的定位是：

```text
把一个已经存在的 FastAPI 仓库接入平台 GitOps 流程
```

注意，它不是从零生成一个完整业务项目，而是接入已有服务。

它会为这个服务生成：

- Crossplane `AppService` Helm chart。
- Argo CD `Application`。
- Backstage `catalog-info.yaml`。
- Tekton CI 入口，包括 Pipeline、EventListener、TriggerBinding、TriggerTemplate。
- 一个 GitHub Pull Request，等待合并到 GitOps 仓库。

## 3. 使用模板前需要准备什么

使用模板前，需要准备以下信息。

### 3.1 应用代码仓库

例如：

```text
https://github.com/Re1lya/fastapi-demo-2.git
```

这个仓库需要满足当前模板默认假设：

- 是 FastAPI 或类似 Python 服务。
- 有 Dockerfile，或者当前 Tekton build task 能构建它。
- 有可测试的 Python 依赖和测试入口。
- 服务在容器内监听一个明确端口，例如 `8000`。

### 3.2 镜像仓库

例如：

```text
ghcr.io/re1lya/fastapi-demo-2
```

Tekton 构建后会推送：

```text
ghcr.io/re1lya/fastapi-demo-2:<commit_sha>
```

### 3.3 GitOps 仓库

当前 POC 使用：

```text
https://github.com/Re1lya/Markdown.git
```

模板会把生成的文件提交到这个仓库的 PR 中。

### 3.4 平台基础组件

模板只是生成资源文件。要真正跑起来，集群里需要已经装好：

- Crossplane。
- Tekton Pipelines。
- Tekton Triggers。
- Argo CD。
- Backstage。
- Envoy Gateway 或其他服务入口组件。
- GHCR / GitHub 所需 Secret。

### 3.5 部署前置条件与职责边界

Backstage 模板负责生成平台接入所需的 GitOps 文件和 Pull Request，但它依赖平台底座已经准备完成。

```text
平台底座准备阶段：
Kubernetes、Crossplane、Tekton、Argo CD、Backstage、Secret、镜像仓库、网络入口需要提前可用。

服务接入阶段：
通过 Backstage 模板填写服务参数，生成 GitOps PR，合并后由 Argo CD / Crossplane / Kubernetes 完成部署。
```

服务接入时需要确认的关键输入：

| 输入 | 作用 |
| --- | --- |
| 服务名 | 会变成 Backstage 组件名、Kubernetes 资源名、CI 资源名前缀 |
| 代码仓库 | Tekton 会从这里 clone 代码 |
| 镜像仓库 | Tekton 会把构建出来的镜像推到这里 |
| 端口 | Kubernetes 需要知道容器监听哪个端口 |
| GitOps PR | 模板生成的配置需要合并后才会被 Argo CD 同步 |

因此，模板覆盖的是“服务接入流程”，不是“平台底座安装流程”。底座安装、Secret 配置、镜像仓库权限和网络入口仍属于平台维护范围。

## 4. 在 Backstage 上使用模板的流程

### 4.1 打开 Backstage

本机访问一般是：

```text
http://localhost:7007
```

如果 Backstage 跑在服务器上，常用方式是：

```bash
kubectl -n backstage port-forward svc/backstage 7007:7007
ssh -L 7007:127.0.0.1:7007 admin@服务器地址
```

然后浏览器打开：

```text
http://localhost:7007/create
```

### 4.2 选择模板

在 Create 页面选择：

```text
Register Existing FastAPI Service
```

如果看不到该模板，通常是 Backstage 没有加载模板 location，见本文第 10 节。

### 4.3 填写 Service 信息

模板第一组参数是 Service：

| 参数 | 含义 | 示例 |
| --- | --- | --- |
| `serviceName` | Kubernetes 和 Backstage 中的服务名 | `fastapi-demo-2` |
| `owner` | Backstage owner | `platform-team` |
| `sourceRepoUrl` | 应用 GitHub 页面地址 | `https://github.com/Re1lya/Markdown` |
| `sourceRepoCloneUrl` | Tekton clone 用的仓库地址 | `https://github.com/Re1lya/Markdown.git` |
| `sourceBranch` | 应用分支 | `main` |
| `contextDir` | Dockerfile / tests 所在目录 | `apps/fastapi-demo` |
| `imageRepository` | 镜像仓库，不带 tag | `ghcr.io/re1lya/fastapi-demo-2` |

### 4.4 填写 Runtime 信息

| 参数 | 含义 | 示例 |
| --- | --- | --- |
| `runtimeNamespace` | 应用最终运行 namespace | `demo` |
| `crossplaneNamespace` | Crossplane Claim 所在 namespace | `default` |
| `appPort` | 容器监听端口 | `8000` |
| `replicas` | 副本数 | `1` |

### 4.5 填写 GitOps 仓库信息

| 参数 | 含义 | 示例 |
| --- | --- | --- |
| `gitopsRepoUrl` | Backstage publish action 使用的 repoUrl | `github.com?owner=Re1lya&repo=Markdown` |
| `gitopsHttpUrl` | Argo CD / Tekton clone 用的 Git URL | `https://github.com/Re1lya/Markdown.git` |
| `gitopsTargetBranch` | 目标分支 | `main` |

### 4.6 执行模板

点击运行后，Backstage 会执行模板 steps，最后创建一个 GitHub PR。

模板成功后，输出中会包含：

- Pull Request 链接。
- Catalog file 链接。
- Tekton CI file 链接。

### 4.7 标准操作流程

平台底座可用后，服务接入的标准操作流程如下：

```text
1. 打开 Backstage 的 Create 页面
2. 选择 Register Existing FastAPI Service
3. 填写服务名、owner、代码仓库、clone URL、镜像仓库、端口、namespace
4. 点击创建
5. 打开模板输出的 GitHub Pull Request
6. 检查生成文件里的服务名、镜像仓库、端口是否正确
7. 合并 PR
8. 等待 Argo CD 同步
9. 在 Backstage Catalog 搜索服务名
10. 点击 Source Repository 或 Open Service 验证
```

这个流程不直接手写 `kubectl apply`。如果 Argo CD 同步、Crossplane 资源创建、Pod 启动或 Tekton PipelineRun 失败，需要进入对应组件排查。

## 5. 模板具体生成什么文件

假设服务名是：

```text
my-api
```

模板会生成下面这些文件。

### 5.1 AppService Helm chart

```text
crossplane-backstage-poc/gitops/appservices/my-api/Chart.yaml
crossplane-backstage-poc/gitops/appservices/my-api/values.yaml
crossplane-backstage-poc/gitops/appservices/my-api/templates/appservice.yaml
```

它的作用是声明一个 Crossplane `AppService`：

```yaml
apiVersion: platform.example.com/v1alpha1
kind: AppService
metadata:
  name: my-api
spec:
  namespace: demo
  chartName: fastapi-demo
  chartVersion: 0.1.0
  port: 8000
  replicas: 1
  image:
    repository: ghcr.io/re1lya/my-api
    tag: latest
```

后续 Tekton 成功后会把 `values.yaml` 里的 image tag 更新为新的 commit sha。

### 5.2 Argo CD Application

```text
crossplane-backstage-poc/gitops/argocd/my-api-appservice.yaml
```

它告诉 Argo CD 去同步：

```text
crossplane-backstage-poc/gitops/appservices/my-api
```

也就是同步刚才生成的 AppService Helm chart。

### 5.3 Backstage Catalog

```text
crossplane-backstage-poc/catalog/services/my-api/catalog-info.yaml
```

它让 Backstage Catalog 里出现这个服务。

里面包含：

- 服务名。
- owner。
- Kubernetes annotation。
- source repository link。

当前模板默认只生成 Source Repository 链接。如果还想在页面上显示 `Open Service`，需要补充：

```yaml
links:
  - url: https://github.com/xxx/my-api
    title: Source Repository
    icon: github
  - url: http://服务器IP:30080/
    title: Open Service
    icon: web
```

### 5.4 Tekton CI 入口

```text
crossplane-backstage-poc/gitops/tekton/my-api-ci.yaml
```

它包含：

- ServiceAccount。
- RoleBinding。
- ClusterRoleBinding。
- Pipeline。
- TriggerBinding。
- TriggerTemplate。
- EventListener。

整体作用是：

```text
GitHub push / 手动 curl
  -> EventListener
  -> TriggerTemplate
  -> PipelineRun
  -> clone
  -> test
  -> build-push
  -> update-gitops
```

## 6. 合并 PR 后会发生什么

Backstage 模板本身只是创建 PR。真正部署发生在 PR 合并之后。

合并后链路是：

```text
GitOps 仓库出现新文件
  -> Argo CD 发现新的 Application
  -> Argo CD 同步 AppService Helm chart
  -> Crossplane 处理 AppService
  -> Kubernetes 中创建 Deployment / Service 等资源
  -> Backstage Catalog provider 刷新后显示新服务
```

CI/CD 触发后链路是：

```text
应用代码 push
  -> Tekton PipelineRun
  -> 构建并推送镜像
  -> 修改 GitOps values.yaml 的 image tag
  -> push GitOps 仓库
  -> Argo CD 同步新镜像
  -> Kubernetes 滚动更新
```

### 6.1 从创建到上线的状态变化

| 阶段 | 谁在工作 | 成功标志 | 如果失败看哪里 |
| --- | --- | --- | --- |
| 填写模板 | 开发者 / Backstage | Backstage 任务完成并输出 PR | Backstage task 日志 |
| 生成 PR | Backstage Scaffolder | GitHub 上出现 onboarding PR | Backstage publish action 日志 |
| 合并 PR | 人工 Review | GitOps 仓库出现新目录和 YAML | GitHub PR diff |
| 同步 Application | Argo CD | Application 变为 `Synced` / `Healthy` | Argo CD Application 状态 |
| 创建 AppService | Crossplane | `kubectl get appservice -A` 能看到服务 | Crossplane events / provider logs |
| 创建运行资源 | Kubernetes | `demo` namespace 出现 Pod / Service | `kubectl describe pod` / events |
| 触发 CI | Tekton | 出现新的 PipelineRun | `kubectl -n ci get pipelinerun` |
| 更新镜像版本 | Tekton + GitOps | `values.yaml` image tag 变成 commit sha | PipelineRun task logs |
| 滚动更新 | Argo CD + Kubernetes | 新 Pod 使用新镜像并 Running | Argo CD / Pod events |

### 6.2 这条链路里每个组件负责什么

```text
Backstage：收集参数，生成文件，创建 PR，展示服务目录。
GitHub：保存源码、GitOps 文件和 PR 历史。
Tekton：在代码变化后构建镜像，并把新镜像 tag 写回 GitOps。
Argo CD：持续把 GitOps 仓库里的目标状态同步到集群。
Crossplane：把 AppService 这种平台抽象转成底层资源组合。
Helm：渲染 AppService chart 或平台组件 chart。
Kubernetes：真正运行 Deployment、Pod、Service。
Envoy Gateway：把服务暴露给浏览器访问。
```

如果只记一句话：

```text
Backstage 负责入口，GitHub 负责状态，Tekton 负责构建，Argo CD 负责同步，Crossplane/Helm 负责生成资源，Kubernetes 负责运行。
```

## 7. 如何验证服务创建成功

### 7.1 看 Backstage Catalog

打开：

```text
http://localhost:7007/catalog
```

搜索服务名，例如：

```text
my-api
```

### 7.2 看 Argo CD Application

```bash
kubectl -n argocd get applications
```

应该能看到：

```text
my-api-appservice
```

### 7.3 看 Crossplane AppService

```bash
kubectl get appservice -A
```

### 7.4 看应用 Pod 和 Service

```bash
kubectl -n demo get deploy,pod,svc
```

### 7.5 看 Tekton CI

```bash
kubectl -n ci get pipeline,task,eventlistener
kubectl -n ci get pipelinerun --sort-by=.metadata.creationTimestamp
```

## 8. 当前模板适用范围

当前模板适合：

- FastAPI 服务。
- 镜像构建逻辑和 `fastapi-demo` 类似的 Python 服务。
- 使用 GitHub 仓库。
- 使用 GHCR 或类似镜像仓库。
- 使用当前平台的 `AppService` 抽象。
- 服务只需要简单端口、replicas、image 配置。

当前模板不太适合：

- Java Spring Boot 服务。
- Node.js / React 前端服务。
- 多容器应用。
- 需要数据库、Redis、消息队列等依赖资源的服务。
- 需要 Ingress path、域名、TLS、环境变量、Secret、ConfigMap 的复杂服务。
- 不使用 GitHub 的仓库。
- 不使用 Dockerfile 或当前 build task 无法构建的项目。

### 8.1 使用前的判断清单

使用模板前建议先问 8 个问题：

| 问题 | 如果答案是否定的怎么办 |
| --- | --- |
| 服务是否已有 Git 仓库？ | 先创建或迁移代码仓库 |
| 服务是否能用当前 Tekton task 构建？ | 新增或修改构建 task |
| 服务是否有 Dockerfile 或等价构建方式？ | 先补 Dockerfile 或改 build task |
| 服务是否只需要单端口暴露？ | 多端口需要扩展 AppService / Helm chart |
| 服务是否只需要简单 Deployment / Service？ | 复杂依赖需要扩展平台抽象 |
| 镜像仓库是否可写？ | 先配置 GHCR token / imagePullSecret |
| GitOps 仓库是否可写？ | 先配置 GitHub token 权限 |
| Backstage 是否能发现模板？ | 检查 catalog locations 和镜像是否更新 |

如果这些问题里有多项是否定的，不建议强行使用当前 FastAPI 模板。

## 9. 如果别的服务进来，模板不适用怎么办

不要强行套模板。先判断差异属于哪一类。

### 9.1 只是参数不同

例如：

- 端口不同。
- replicas 不同。
- namespace 不同。
- 镜像仓库不同。
- contextDir 不同。

这种情况不需要新建模板，直接用现有模板填不同参数即可。

### 9.2 需要多几个可配置字段

例如服务需要：

- 环境变量。
- health check path。
- service path。
- Open Service URL。
- image tag 默认值。

这种情况可以扩展现有模板：

1. 在 `template.yaml` 的 `parameters` 中新增字段。
2. 在 `skeleton/*.njk` 中使用这些字段。
3. 重新构建并部署 Backstage 镜像。
4. 在 Backstage Create 页面测试新字段。

示例：给模板新增 `serviceUrl` 参数，用于生成 `Open Service`：

```yaml
serviceUrl:
  title: Service URL
  type: string
  description: Public URL shown in Backstage Open Service link.
```

然后在 `catalog-info.yaml.njk` 中加入：

```yaml
  links:
    - url: ${{ values.sourceRepoUrl }}
      title: Source Repository
      icon: github
    - url: ${{ values.serviceUrl }}
      title: Open Service
      icon: web
```

### 9.3 构建流程不同

例如 Java 服务需要：

```text
mvn test
mvn package
docker build
```

而不是 Python/FastAPI 的测试方式。

这时不要只改参数，应该新增或拆分 Tekton Task：

- `test-java-service`
- `build-push-java-service`
- `update-java-gitops`

然后可以选择：

```text
方案 A：新建 register-existing-java-service 模板
方案 B：在一个通用模板中加入 language 参数，根据 language 生成不同 Pipeline
```

POC 阶段更推荐方案 A，因为更清晰，排障更容易。

### 9.4 运行时资源不同

例如服务需要：

- MySQL。
- Redis。
- ConfigMap。
- Secret。
- 定时任务。
- 多个 Deployment。

这时需要扩展平台抽象，而不只是改 Backstage 模板。

可能需要：

1. 修改 Crossplane XRD。
2. 修改 Composition。
3. 修改 AppService spec。
4. 修改 Helm chart。
5. 修改 Backstage template 生成的 values。

也就是说：

```text
Backstage template 只是入口
Crossplane / Helm 才是真正决定集群里能创建什么资源
```

### 9.5 GitOps 管理方式不同

如果一个服务不是用当前 GitOps 仓库管理，而是有自己的 GitOps 仓库，需要修改：

- Argo CD Application 的 `repoURL`。
- `path`。
- `targetRevision`。
- Tekton update-gitops task 的仓库地址和 values 文件路径。

这种情况建议新建模板，避免把当前 POC 的 GitOps 路径写得过于复杂。

## 10. 如何创建一个新的 Backstage Template

### 10.1 复制现有模板目录

例如创建 Java 服务模板：

```text
crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-java-service
```

可以从现有目录复制：

```text
crossplane-backstage-poc/apps/backstage-custom/templates/register-existing-fastapi
```

### 10.2 修改 template.yaml

必须改：

```yaml
metadata:
  name: register-existing-java-service
  title: Register Existing Java Service
  description: ...
  tags:
    - java
    - gitops
    - crossplane
```

然后根据 Java 服务新增或调整参数，例如：

- `javaVersion`
- `buildCommand`
- `artifactPath`
- `healthPath`
- `containerPort`

### 10.3 修改 skeleton 文件

常见需要改的文件：

```text
skeleton/catalog-info.yaml.njk
skeleton/tekton-ci.yaml.njk
skeleton/values.yaml.njk
skeleton/appservice.yaml.njk
skeleton/argocd-application.yaml.njk
```

如果只是 Catalog 展示不同，改 `catalog-info.yaml.njk`。

如果 CI 不同，改 `tekton-ci.yaml.njk`。

如果部署参数不同，改 `values.yaml.njk` 和 `appservice.yaml.njk`。

如果 GitOps 路径不同，改 `argocd-application.yaml.njk`。

### 10.4 让 Backstage 能发现新模板

模板目录存在不代表 Backstage 页面能看到。

需要在 Backstage 配置中加入 catalog location，例如：

```yaml
catalog:
  locations:
    - type: file
      target: ./templates/register-existing-java-service/template.yaml
      rules:
        - allow: [Template]
```

当前 production config 中已有示例 template：

```yaml
- type: file
  target: ./examples/template/template.yaml
  rules:
    - allow: [Template]
```

如果自定义模板没有出现在 Create 页面，优先检查这里。

### 10.5 重新构建并部署 Backstage

因为 Dockerfile 会把模板目录复制进镜像：

```text
COPY --chown=node:node templates /app/templates
```

所以新增模板后通常需要：

1. 构建 Backstage 新镜像。
2. 推送镜像。
3. 更新 Backstage Helm values 中的 image tag。
4. 重启或升级 Backstage。

## 11. 模板设计建议

### 11.1 不要把一个模板做得过于万能

一个模板如果同时支持 FastAPI、Java、Node、前端、多容器、多数据库，参数会非常复杂，出错也难排查。

建议：

```text
一个模板覆盖一种明确服务类型
```

例如：

- `register-existing-fastapi-service`
- `register-existing-java-service`
- `register-existing-frontend-service`
- `register-existing-worker-service`

### 11.2 把平台通用能力沉到 Crossplane / Helm

Backstage Template 不应该承载所有平台逻辑。它更像表单和代码生成器。

更合理的分层是：

```text
Backstage Template：收集参数，生成 GitOps 文件
Crossplane：定义平台资源抽象
Helm：渲染 Kubernetes 资源
Argo CD：同步 GitOps 状态
Tekton：执行 CI 和更新镜像版本
```

### 11.3 模板输出要可 Review

模板不要直接把东西悄悄 apply 到集群。当前模板选择创建 GitHub PR 是合理的，因为：

- 人可以 Review 生成的 YAML。
- 出错可以在合并前发现。
- GitOps 历史可追踪。
- Argo CD 有明确同步来源。

## 12. 快速判断：改参数、改模板、还是改平台抽象

| 场景 | 推荐动作 |
| --- | --- |
| 只是服务名、端口、镜像仓库不同 | 直接使用现有模板 |
| 需要 Open Service URL、health path、环境变量 | 扩展现有模板参数 |
| Java / Node / 前端等构建方式不同 | 新建专用模板或专用 Tekton task |
| 需要数据库、Redis、Secret、ConfigMap | 扩展 Crossplane AppService 和 Helm chart |
| GitOps 仓库结构不同 | 新建模板更清晰 |
| 只想把服务显示在 Backstage Catalog | 只新增 `catalog-info.yaml`，不必走完整 CI/CD 模板 |
| 已经有完整 Kubernetes YAML | 可以做“register existing k8s app”模板，只生成 Catalog 和 Argo CD Application |

## 13. 当前模板的后续优化建议

建议后续补强：

1. 给模板增加 `serviceUrl` 参数，自动生成 `Open Service` 链接。
2. 给模板增加 `healthPath` 参数，便于健康检查和运行状态验证。
3. 给模板增加 `imageTag` 默认策略，避免初始值永远是 `latest`。
4. 把 FastAPI 专属 Tekton task 和通用 task 边界拆清楚。
5. 新增 Java / Spring Boot 服务模板。
6. 新增“只注册已有服务到 Catalog”的轻量模板。
7. 在模板输出中增加后续操作提示，例如“PR 合并后检查 Argo CD Application”。
8. 增加模板参数校验，避免 repo URL、image repository、serviceName 填错。
