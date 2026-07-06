┌──────────────────────────┐
│ Backstage / Dev Portal   │
│ - 服务目录               │
│ - 模型服务页面           │
│ - CI/CD 状态             │
│ - Monitoring 面板        │
│ - 限流 / 鉴权配置入口    │
└─────────────┬────────────┘
              ↓
┌──────────────────────────┐
│ Platform API             │
│ - 权限校验               │
│ - 参数校验               │
│ - 业务逻辑               │
└─────────────┬────────────┘
              ↓
┌──────────────────────────┐
│ Crossplane               │
│ - ModelService CRD       │
│ - MicroService CRD       │
│ - GatewayPolicy CRD      │
│ - Composition 编排       │
└─────────────┬────────────┘
              ↓
┌──────────────────────────┐
│ 底层系统                 │
│ - Kubernetes             │
│ - Tekton                 │
│ - KServe / Seldon        │
│ - agentGateway           │
│ - Prometheus / Grafana   │
└──────────────────────────┘