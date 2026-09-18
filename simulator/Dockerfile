FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY logitrack_sim logitrack_sim
CMD ["python","-m","logitrack_sim.main"]

