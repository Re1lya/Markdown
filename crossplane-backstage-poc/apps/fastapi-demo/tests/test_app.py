from fastapi.testclient import TestClient

from app.main import app


def test_root_returns_service_message():
    client = TestClient(app)

    response = client.get("/")

    assert response.status_code == 200
    assert response.json() == {
        "service": "fastapi-demo",
        "message": "hello from fastapi demo",
    }


def test_health_returns_ok():
    client = TestClient(app)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
