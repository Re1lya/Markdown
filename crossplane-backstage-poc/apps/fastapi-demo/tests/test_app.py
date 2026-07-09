from fastapi.testclient import TestClient

from app.main import app


def test_root_returns_service_message():
    client = TestClient(app)

    response = client.get("/")

    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "Platform POC Service is Running" in response.text
    assert "Deployed by Tekton, synced by Argo CD, managed with Crossplane" in response.text
    assert "FastAPI Demo" in response.text


def test_health_returns_ok():
    client = TestClient(app)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
