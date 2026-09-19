FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN useradd --create-home --uid 10001 appuser
COPY --chown=appuser:appuser logitrack_sim logitrack_sim
USER appuser
CMD ["python","-m","logitrack_sim.main"]
