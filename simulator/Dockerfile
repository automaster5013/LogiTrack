FROM python:3.12-slim@sha256:2f17fc044b579bab302c2e8054d3a686e2cb9a83de48e70534b94cd8ebbe06a9
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN useradd --create-home --uid 10001 appuser
COPY --chown=appuser:appuser logitrack_sim logitrack_sim
USER appuser
ENV SIMULATOR_HEALTH_FILE=/tmp/logitrack-simulator-heartbeat
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import os,time; p=os.environ['SIMULATOR_HEALTH_FILE']; assert time.time() - os.path.getmtime(p) < 5"
CMD ["python","-m","logitrack_sim.main"]
