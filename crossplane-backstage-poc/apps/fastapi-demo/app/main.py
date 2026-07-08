from fastapi import FastAPI

app = FastAPI(title="fastapi-demo")


@app.get("/")
def root() -> dict[str, str]:
    return {
        "service": "fastapi-demo",
        "message": "hello from fastapi demo",
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
#这是一个注释用于对CI做测试。