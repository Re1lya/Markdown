from fastapi import FastAPI
from fastapi.responses import HTMLResponse

app = FastAPI(title="fastapi-demo")

SUCCESS_PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Platform POC Service</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f3f7fb;
      --panel: #fbfdff;
      --text: #152333;
      --muted: #64748b;
      --line: #d9e4ef;
      --ok: #168a5b;
      --ok-bg: #e6f6ef;
      --blue: #2364aa;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 32px;
      background:
        radial-gradient(circle at top left, #d7ecff 0, transparent 30%),
        linear-gradient(135deg, var(--bg), #eef5f2);
      color: var(--text);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    main {
      width: min(920px, 100%);
      padding: 40px;
      border: 1px solid var(--line);
      border-radius: 18px;
      background: var(--panel);
      box-shadow: 0 24px 80px rgba(28, 45, 64, 0.12);
    }

    .status {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      padding: 8px 14px;
      border-radius: 999px;
      background: var(--ok-bg);
      color: var(--ok);
      font-size: 14px;
      font-weight: 700;
    }

    .status::before {
      content: "";
      width: 10px;
      height: 10px;
      border-radius: 50%;
      background: var(--ok);
      box-shadow: 0 0 0 5px rgba(22, 138, 91, 0.12);
    }

    h1 {
      margin: 24px 0 10px;
      font-size: clamp(34px, 6vw, 64px);
      line-height: 1.02;
      letter-spacing: 0;
    }

    .subtitle {
      max-width: 720px;
      margin: 0 0 30px;
      color: var(--muted);
      font-size: 18px;
      line-height: 1.6;
    }

    .facts {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
      margin: 30px 0;
    }

    .fact {
      padding: 18px;
      border: 1px solid var(--line);
      border-radius: 12px;
      background: #f8fbfe;
    }

    .label {
      color: var(--muted);
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
    }

    .value {
      margin-top: 6px;
      font-size: 17px;
      font-weight: 800;
    }

    .flow {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 8px;
      padding-top: 6px;
    }

    .flow span {
      padding: 9px 12px;
      border-radius: 10px;
      background: #edf4fb;
      color: #29445f;
      font-size: 14px;
      font-weight: 700;
    }

    .flow b {
      color: var(--blue);
      font-weight: 800;
    }

    footer {
      margin-top: 28px;
      padding-top: 20px;
      border-top: 1px solid var(--line);
      color: var(--muted);
      font-size: 14px;
    }

    @media (max-width: 720px) {
      body {
        padding: 18px;
      }

      main {
        padding: 28px;
      }

      .facts {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <main>
    <div class="status">HTTP 200 OK</div>
    <h1>Platform POC Service is Running</h1>
    <p class="subtitle">Deployed by Tekton, synced by Argo CD, managed with Crossplane.</p>

    <section class="facts" aria-label="service details">
      <div class="fact">
        <div class="label">Service</div>
        <div class="value">FastAPI Demo</div>
      </div>
      <div class="fact">
        <div class="label">Environment</div>
        <div class="value">Kubernetes / kind</div>
      </div>
      <div class="fact">
        <div class="label">Gateway</div>
        <div class="value">Envoy Gateway</div>
      </div>
    </section>

    <div class="flow" aria-label="delivery flow">
      <span>GitHub</span><b>→</b>
      <span>Tekton CI</span><b>→</b>
      <span>GHCR</span><b>→</b>
      <span>Argo CD</span><b>→</b>
      <span>Kubernetes</span><b>→</b>
      <span>Gateway</span>
    </div>

    <footer>Crossplane Backstage Platform Proof of Concept</footer>
  </main>
</body>
</html>"""


@app.get("/")
def root() -> HTMLResponse:
    return HTMLResponse(SUCCESS_PAGE)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
# manual ci test
