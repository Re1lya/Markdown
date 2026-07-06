# OKD / OpenShift Developer Console 方案说明

## 1. 方案定位

OKD 是 OpenShift 的开源社区版，是一套完整的 Kubernetes 发行版，而不仅仅是一个 UI 或 Dev Portal 框架。

它在 Kubernetes 之上集成了 Web Console、认证、CI/CD、监控、Operator、日志、网络与多租户能力。

OKD Developer Console 是 OKD Web Console 的开发者视角，主要用于应用开发、部署、运维和资源状态查看。

---

## 2. 核心能力范围

OKD 生态主要提供以下能力：

* Kubernetes 集群管理
* Developer / Admin Console
* 项目与 Namespace 管理
* 应用拓扑视图
* Pod / Deployment / Service / Route 管理
* CI/CD，基于 OpenShift Pipelines / Tekton
* 日志、事件、Metrics
* 监控与告警
* Operator 生命周期管理
* 多租户与 RBAC
* 镜像构建与镜像仓库
* GitOps / 应用交付支持

---

## 3. 架构结构

```text
用户
  ↓
OKD / OpenShift Developer Console
  ↓
原生能力：
  - Project / Namespace
  - Topology 应用拓扑
  - Workloads：Pod / Deployment
  - Routes / Services
  - Pipelines：Tekton
  - Logs / Events
  - Metrics / Alerts
  - Operators
  ↓
扩展能力：Dynamic Plugin
  - 自定义业务页面
  - 模型服务管理
  - agentGateway 控制面
  - 限流 / 鉴权 / Token 配置
  - 模型监控 Dashboard
  ↓
底层系统：
  - Kubernetes / OKD
  - Tekton Pipelines
  - Prometheus / Grafana
  - KServe / Seldon
  - agentGateway
```

---

## 4. CI/CD 能力

OKD 使用 OpenShift Pipelines 实现 CI/CD，底层基于 Tekton。

主要能力包括：

* Git → Build → Image → Deploy
* Pipeline 可视化
* PipelineRun 状态查看
* Task / Step 级日志
* 多环境发布支持

适合用于：

* 微服务交付
* 模型服务部署
* 镜像构建
* 自动化发布流程

---

## 5. Monitoring 能力

OKD 提供集成监控能力。

主要包括：

* 应用级 Metrics，例如 CPU、内存、网络
* Pod / Deployment 健康状态
* 集群监控，通常基于 Prometheus
* 日志能力，可接 Loki / Elasticsearch 生态
* Kubernetes Events
* 告警系统

适合展示：

* 微服务运行状态
* 模型服务运行状态
* Pod / 节点资源情况
* 基础 SLA 指标

不原生覆盖：

* 模型质量，例如 accuracy / drift
* Token 使用成本
* Prompt 成功率
* RAG 命中率
* 模型版本质量对比

这些能力需要通过 MLflow、Evidently、agentGateway 指标或自研模型观测服务补充。

---

## 6. 登录与认证体系

OKD 使用 OAuth Server 管理认证。

```text
用户
  ↓
OKD OAuth Server
  ↓
Identity Provider
  - LDAP
  - OIDC
  - GitHub
  - GitLab
  - Keycloak
  ↓
Token 访问 API / Console
```

OKD 支持外部身份源，但整体仍运行在 OKD / OpenShift 的认证体系内。

---

## 7. 扩展方式

### 7.1 Dynamic Plugin

Dynamic Plugin 是更推荐的扩展方式。

特点：

* 在 OpenShift Console 中增加自定义页面
* 可以接入外部 API
* 不破坏原生 Console
* 适合扩展业务能力

可扩展内容：

* 模型服务 UI
* agentGateway 配置 UI
* 限流 / Token 管理
* 模型监控 Dashboard
* 自定义 Pipeline 面板
* 自定义业务运维页面

### 7.2 Fork Console

Fork Console 是深度二开方式，但一般不推荐。

原因：

* 需要修改 OpenShift Console 源码
* 与 OKD / OpenShift 耦合较深
* 升级维护成本高
* 需要理解 OpenShift 内部资源、权限和 Console 架构

---

## 8. 优点

### 8.1 平台能力完整

OKD 内置 Kubernetes、DevOps、Monitoring、Logging、RBAC、Operator 等能力，适合作为完整平台底座。

### 8.2 Developer Console 成熟

Developer Console 支持：

* 从 Git 创建应用
* 应用拓扑视图
* CI/CD Pipeline 可视化
* 资源状态查看
* 日志和 Metrics 查看

### 8.3 Tekton 原生支持

OpenShift Pipelines 基于 Tekton，适合现代 Kubernetes-native CI/CD 架构。

### 8.4 Monitoring 集成较完整

OKD 原生集成 Prometheus、Console Metrics、应用健康状态等能力，适合微服务和基础设施监控。

### 8.5 支持插件扩展

通过 Console Dynamic Plugin 可以扩展自定义业务 UI，例如模型服务、agentGateway、限流、Token 额度、模型监控等页面。

### 8.6 认证体系完善

OKD 支持 OAuth，并可以接入外部 Identity Provider，例如 OIDC、LDAP、GitHub、GitLab、Keycloak 等。

---

## 9. 局限性

### 9.1 平台绑定较强

OKD Console 高度依赖 OKD / OpenShift 生态，例如 OAuth、Operator、Route、Console Operator 等。

### 9.2 不适合作为通用 Dev Portal 框架

它不是 Backstage 那种通用插件化 Dev Portal 框架，整体信息架构更偏 OpenShift / Kubernetes 平台控制台。

### 9.3 模型平台能力不足

OKD 不原生支持：

* 模型版本管理 UI
* 模型质量监控
* Token / Cost 监控
* Prompt / RAG 指标
* 模型路由与灰度切换页面

这些需要结合 KServe、Seldon、MLflow、Evidently、agentGateway 或自研服务实现。

### 9.4 深度二开成本较高

如果不是通过 Dynamic Plugin 扩展，而是直接改 Console 源码，维护成本会比较高。

### 9.5 UI 定制自由度有限

OKD Console 可以通过插件扩展，但不适合完全自由地重构门户结构、导航体系和产品形态。

---

## 10. 与 Backstage 对比

| 维度         | OKD Console                     | Backstage     |
| ---------- | ------------------------------- | ------------- |
| 定位         | Kubernetes / OpenShift 平台控制台    | Dev Portal 框架 |
| UI 自由度     | 中                               | 高             |
| K8s 支持     | 原生强                             | 通过插件接入        |
| CI/CD      | OpenShift Pipelines / Tekton 原生 | 通过插件集成        |
| Monitoring | 原生整合较多                          | 通过插件集成        |
| 扩展方式       | Console Dynamic Plugin          | React 插件体系    |
| 平台绑定       | 强                               | 弱             |
| 适合场景       | 使用 OKD / OpenShift 的平台控制台       | 自定义开发者门户      |

---

## 11. 与 Crossplane 对比

| 维度               | OKD Console    | Crossplane   |
| ---------------- | -------------- | ------------ |
| 角色               | UI 控制台         | 控制平面         |
| 是否提供 UI          | 是              | 否            |
| 是否管理资源           | 可以管理和展示 K8s 资源 | 负责声明式资源编排    |
| 是否做资源编排          | 不是核心能力         | 是核心能力        |
| 是否适合做 Dev Portal | 可作为基础控制台       | 不适合做 UI      |
| 主要价值             | 展示、操作、管理平台资源   | 把平台声明转换成底层资源 |

---

## 12. 在模型 / 微服务平台中的使用方式

OKD Console 适合做基础控制台，并通过插件扩展模型和网关能力。

```text
OKD Console
  ├── Kubernetes 资源视图
  ├── Pipeline / CI/CD
  ├── 应用拓扑
  ├── Logs / Metrics
  ├── Events / Alerts
  └── 自定义 Plugin
        ├── 模型服务管理
        ├── agentGateway 控制
        ├── 模型版本切换
        ├── Token / 限流管理
        └── 模型监控
```

底层可组合：

* Tekton / OpenShift Pipelines：CI/CD
* KServe / Seldon：模型服务
* agentGateway：鉴权、限流、模型路由
* Prometheus / Grafana：运行指标监控
* MLflow / Evidently：模型质量与评估
* Crossplane：资源声明式编排

---

## 13. 适用场景

适合：

* 基于 Kubernetes 构建企业级平台
* 需要完整 DevOps + Monitoring + UI
* 使用 Tekton / OpenShift Pipelines
* 接受 OKD / OpenShift 生态绑定
* 需要成熟 Developer Console
* 希望通过插件扩展部分业务能力

不适合：

* 想做完全自定义 Dev Portal
* 想脱离 OKD / OpenShift 生态
* 想高度自由设计 UI 和信息架构
* 模型平台 / Agent 平台是核心业务系统
* 希望所有模型治理能力开箱即用

---

## 14. 总结

OKD / OpenShift Developer Console 是一个完整 Kubernetes 平台控制台，而不是通用 Dev Portal 框架。

它适合：

* 直接作为开发者控制台使用
* 作为 Kubernetes / OpenShift 平台 UI
* 通过 Dynamic Plugin 扩展业务能力

它不适合：

* 作为完全自由的 Dev Portal 底座
* 作为高度自定义模型平台 UI 框架
* 作为脱离 OKD / OpenShift 生态的独立客户端

其核心价值在于：

> 提供一个完整的 Kubernetes + DevOps + Monitoring + Pipeline + UI 统一平台，并允许通过插件扩展业务能力。
