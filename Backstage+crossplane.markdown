# Backstage + Crossplane 联合方案

## 1. 方案定位

Backstage 和 Crossplane 不是同类工具，可以同时使用，分别满足不同层面的需求。

| 组件                   | 定位                   | 核心作用                            |
| -------------------- | -------------------- | ------------------------------- |
| Backstage            | Dev Portal / 开发者门户   | 提供客户端 UI、服务目录、插件页面、操作入口         |
| Crossplane           | Control Plane / 控制平面 | 把平台级资源声明编排成真实 Kubernetes / 外部资源 |
| Tekton               | CI/CD 引擎             | 执行构建、测试、部署、回滚等流水线               |
| agentGateway         | 模型/API 网关            | 负责鉴权、限流、路由、Token 额度、调用观测        |
| Prometheus / Grafana | Monitoring           | 采集和展示微服务、模型服务、网关指标              |

核心思路：

> Backstage 负责“让用户看见和操作”，Crossplane 负责“把用户操作变成真实资源”。

---

## 2. 整体架构

用户通过 Backstage 访问统一平台入口。

Backstage 调用自研 Platform API。

Platform API 负责权限校验、参数处理、业务逻辑。

Platform API 创建或更新 Crossplane 平台资源。

Crossplane 根据声明自动创建 Kubernetes、KServe、agentGateway、Monitoring 等底层资源。

Tekton 负责执行 CI/CD 流水线。

Prometheus、Grafana、MLflow、Evidently 等系统负责提供监控和模型观测数据。

---

## 3. 组件分工

| 层级      | 组件                                          | 负责内容                                          |
| ------- | ------------------------------------------- | --------------------------------------------- |
| 门户层     | Backstage                                   | 页面、服务目录、模型服务页面、CI/CD 状态、监控入口                  |
| API 层   | Platform API                                | 权限、参数校验、业务逻辑、统一接口                             |
| 控制平面    | Crossplane                                  | ModelService、MicroService、GatewayPolicy 等资源编排 |
| CI/CD 层 | Tekton                                      | PipelineRun、TaskRun、构建、测试、部署、回滚               |
| 运行层     | Kubernetes                                  | 运行微服务、模型服务、网关、监控组件                            |
| 模型服务层   | KServe / Seldon / Deployment                | 模型推理服务                                        |
| 网关层     | agentGateway                                | 鉴权、限流、模型路由、Token 额度、调用统计                      |
| 监控层     | Prometheus / Grafana / Loki / OpenTelemetry | 指标、日志、链路追踪                                    |
| 模型观测层   | MLflow / Evidently                          | 模型质量、漂移、评估、实验记录                               |

---

## 4. Backstage 负责什么

Backstage 是用户直接看到和操作的客户端门户。

主要能力包括：

| 功能              | 说明                                |
| --------------- | --------------------------------- |
| 服务目录            | 展示微服务、模型服务、API、负责人、文档             |
| CI/CD 页面        | 展示 Pipeline 状态、构建日志、部署记录          |
| 模型服务页面          | 展示模型名称、版本、状态、Endpoint、GPU、延迟      |
| Monitoring 页面   | 展示 QPS、错误率、延迟、资源使用、限流次数           |
| agentGateway 页面 | 管理 API Key、限流策略、模型路由、Token Budget |
| 自助操作            | 创建服务、部署、回滚、切换模型、调整限流              |

Backstage 本身不负责真正部署服务，也不负责真正执行 CI/CD。它主要通过插件或自定义 API，把外部系统能力整合到一个门户中。

---

## 5. Crossplane 负责什么

Crossplane 不负责 UI，而是负责资源抽象和声明式编排。

可以定义平台级资源，例如：

### ModelService

用于描述一个模型服务。

```yaml
apiVersion: platform.example.com/v1alpha1
kind: ModelService
metadata:
  name: qwen-chat
spec:
  model:
    name: qwen-7b
    version: v2
  runtime:
    type: kserve
    replicas: 2
    gpu: 1
  gateway:
    enabled: true
    auth: apiKey
    rateLimit: 1000/min
    tokenBudget: 1000000/day
  monitoring:
    enabled: true
    metrics: true
    alerts: true
```

Crossplane 可以根据该资源自动创建：

* KServe InferenceService 或 Kubernetes Deployment
* Service
* agentGateway Route
* RateLimitPolicy
* API Key / Secret
* ServiceMonitor
* PrometheusRule
* Grafana Dashboard 配置
* ConfigMap / Secret

---

## 6. 典型业务流程

### 6.1 创建模型服务

1. 用户在 Backstage 页面填写模型、版本、副本数、GPU、限流、监控配置。
2. Backstage 调用 Platform API。
3. Platform API 创建 Crossplane 的 ModelService 资源。
4. Crossplane 自动创建模型服务、网关路由、限流策略和监控配置。
5. Tekton 执行构建或部署流程。
6. Backstage 展示服务状态、Pipeline 状态和监控数据。

---

### 6.2 切换模型版本

1. 用户在 Backstage 点击“切换模型”。
2. Backstage 调用 Platform API。
3. Platform API 更新 ModelService 的模型版本。
4. Crossplane 根据变更更新底层资源。
5. 底层可以选择更新 KServe / Deployment，或者更新 agentGateway 路由。
6. 健康检查通过后，Backstage 展示新的当前模型版本。

模型切换可以有两种方式：

| 方式     | 说明                              |
| ------ | ------------------------------- |
| 更新模型服务 | 更新 KServe / Deployment 使用的新模型版本 |
| 更新网关路由 | agentGateway 将模型别名切换到新版本后端      |

---

### 6.3 触发 CI/CD

1. 用户在 Backstage 点击“重新部署”。
2. Backstage 调用 Platform API。
3. Platform API 创建 Tekton PipelineRun。
4. Tekton 执行构建、测试、镜像推送、部署。
5. Backstage 查询 PipelineRun / TaskRun 状态。
6. 页面展示执行进度、任务状态和日志。

---

### 6.4 接入 Monitoring

1. Crossplane 创建 ServiceMonitor、PrometheusRule 等监控资源。
2. Prometheus 采集模型服务、微服务、agentGateway 的指标。
3. Grafana 展示 Dashboard。
4. Backstage 通过插件、嵌入链接或自定义 API 展示监控数据。

常见数据来源：

| 数据类型                | 来源                             |
| ------------------- | ------------------------------ |
| Pod / Deployment 状态 | Kubernetes API                 |
| Pipeline 状态         | Tekton API                     |
| 微服务指标               | Prometheus                     |
| 模型推理指标              | KServe / Seldon / Prometheus   |
| Token / 限流 / 鉴权数据   | agentGateway                   |
| 模型质量指标              | MLflow / Evidently             |
| 日志                  | Loki / Elasticsearch           |
| 链路追踪                | OpenTelemetry / Jaeger / Tempo |

---

## 7. 可以抽象的平台资源

| 资源                | 用途                                |
| ----------------- | --------------------------------- |
| ModelService      | 描述模型服务、模型版本、运行配置、网关策略、监控配置        |
| MicroService      | 描述普通微服务、镜像、副本数、端口、监控配置            |
| GatewayPolicy     | 描述鉴权、限流、Token Budget、模型路由         |
| Environment       | 描述 dev / test / prod 环境、命名空间、资源配额 |
| PipelineTemplate  | 描述构建、测试、部署、回滚流水线模板                |
| MonitoringProfile | 描述监控、告警、日志、Dashboard 配置           |

---

## 8. Backstage 页面规划

| 页面              | 展示内容                                 |
| --------------- | ------------------------------------ |
| 首页 Dashboard    | 我的服务、我的模型、最近部署、最近告警、资源使用             |
| 服务目录            | 微服务、模型服务、API、负责人、文档、运行状态             |
| 模型服务详情          | 当前模型、版本、Endpoint、QPS、延迟、错误率、Token 使用 |
| CI/CD 页面        | PipelineRun、TaskRun、执行阶段、日志、部署结果     |
| Monitoring 页面   | 微服务指标、模型指标、Gateway 指标、GPU 指标         |
| agentGateway 页面 | API Key、限流策略、模型路由、Token Budget、调用统计  |
| 环境管理            | dev / test / prod 环境、资源配额、命名空间、权限    |

---

## 9. 方案优点

### 9.1 职责清晰

Backstage 负责前端门户和用户操作。

Crossplane 负责底层资源抽象和编排。

Tekton 负责流水线执行。

Prometheus / Grafana 负责监控。

agentGateway 负责模型流量治理。

---

### 9.2 扩展性强

Backstage 可以通过插件扩展页面。

Crossplane 可以通过 CRD、XRD、Composition 扩展平台资源。

适合持续增加新的能力，例如模型服务、网关策略、监控模板、环境模板等。

---

### 9.3 适合平台工程

可以把复杂的 Kubernetes、Tekton、KServe、Gateway、Monitoring 配置封装成简单的平台资源。

开发者只需要在门户页面填写表单，不需要直接编写复杂 YAML。

---

### 9.4 适合模型服务场景

可以统一管理：

* 模型部署
* 模型版本切换
* 模型路由
* API Key
* Token 额度
* 限流策略
* 模型监控
* 微服务监控
* CI/CD 状态

---

## 10. 方案局限

### 10.1 系统复杂度较高

该方案涉及多个系统：

* Backstage
* Platform API
* Crossplane
* Tekton
* Kubernetes
* agentGateway
* Prometheus / Grafana
* MLflow / Evidently

整体集成和维护成本较高。

---

### 10.2 需要自研 Platform API

Backstage 和 Crossplane 之间通常需要一层 Platform API。

该 API 负责：

* 用户权限
* 参数校验
* 业务流程
* 调用 Tekton
* 查询 Monitoring
* 管理 agentGateway
* 创建或更新 Crossplane 资源

---

### 10.3 模型监控需要额外系统

Backstage 和 Crossplane 都不直接提供模型质量监控。

模型质量、漂移、Prompt 成功率、Token 成本、RAG 命中率等指标，需要接入 MLflow、Evidently 或自研模型观测服务。

---

### 10.4 Crossplane 设计成本较高

需要设计：

* XRD
* Composition
* Provider
* 资源映射
* 状态回写
* 权限模型
* 多环境隔离

这对平台工程能力有一定要求。

---

## 11. 适用场景

适合：

* 需要构建统一开发者门户
* 需要集成 CI/CD、Monitoring、模型服务和微服务
* 需要支持模型切换、鉴权、限流、Token 额度
* 需要把底层 Kubernetes 和网关能力封装成平台 API
* 团队具备 Kubernetes 和平台工程能力

不适合：

* 只需要简单 CI/CD 页面
* 只需要 Kubernetes Dashboard
* 不希望引入多个平台组件
* 没有自定义资源抽象需求
* 不需要模型服务和 agentGateway 治理能力

---

## 12. 总体形态

最终系统可以形成一个面向开发者的统一平台：

| 层级                                        | 能力                    |
| ----------------------------------------- | --------------------- |
| Backstage                                 | 统一入口、页面、组件、插件、服务目录    |
| Platform API                              | 业务接口、权限校验、参数处理        |
| Crossplane                                | 声明式平台资源和自动编排          |
| Tekton                                    | CI/CD 执行              |
| agentGateway                              | 模型服务鉴权、限流、路由、Token 管理 |
| Prometheus / Grafana / MLflow / Evidently | 微服务和模型监控              |

整体目标是：

> 构建一个可扩展的 Dev Portal，让开发者通过统一页面完成服务创建、模型部署、CI/CD 触发、模型切换、网关配置和监控查看。
