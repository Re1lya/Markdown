from fastapi.testclient import TestClient

from app.main import app


def test_success_page_shows_platform_delivery_chain():
    client = TestClient(app)

    response = client.get("/")

    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "Platform POC Service is Running" in response.text
    assert "Deployed by Tekton, synced by Argo CD, managed with Crossplane" in response.text
    assert "GitHub" in response.text
    assert "Tekton CI" in response.text
    assert "Argo CD" in response.text
    assert "Kubernetes" in response.text
