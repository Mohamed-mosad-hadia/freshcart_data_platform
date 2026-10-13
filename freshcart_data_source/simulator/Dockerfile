FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY simulator ./simulator
USER 10001

ENTRYPOINT ["python", "-m", "simulator"]
CMD ["run"]
