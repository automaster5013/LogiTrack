FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN useradd --create-home --uid 10001 appuser
COPY --chown=appuser:appuser app app
USER appuser
EXPOSE 8090
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8090"]
