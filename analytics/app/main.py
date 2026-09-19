import os
import uuid
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import Body, FastAPI, Response
from pydantic import BaseModel, Field
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from .routing import Coordinate, RoutePlanner
from .reporting import render_daily_kpi_report


class Location(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class RouteRequest(BaseModel):
    origin: Location
    destination: Location


class RouteResponse(BaseModel):
    routeId: uuid.UUID
    provider: str
    algorithmVersion: str
    coordinates: list[list[float]]
    distanceMeters: int
    durationSeconds: int
    plannedEta: datetime
    geometryHash: str
    generatedAt: datetime


class DailyKpiRow(BaseModel):
    metricDate: date
    totalDeliveries: int = Field(ge=0, le=2_147_483_647)
    activeDeliveries: int = Field(ge=0, le=2_147_483_647)
    deliveredDeliveries: int = Field(ge=0, le=2_147_483_647)
    delayedDeliveries: int = Field(ge=0, le=2_147_483_647)
    averageProgressPercent: float = Field(ge=0, le=100)
    averageCycleMinutes: float = Field(ge=0, le=525_600)
    onTimeRatePercent: float = Field(ge=0, le=100)
    projectedAt: datetime


def configure_tracing() -> None:
    if os.getenv("OTEL_SDK_DISABLED", "false").lower() == "true":
        return
    provider = TracerProvider(resource=Resource.create({
        "service.name": os.getenv("OTEL_SERVICE_NAME", "logitrack-route-analytics"),
        "service.instance.id": os.getenv("INSTANCE_ID", "analytics-1"),
    }))
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(
        endpoint=os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "http://localhost:4318/v1/traces")
    )))
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(app, excluded_urls="health")
    HTTPXClientInstrumentor().instrument()

planner = RoutePlanner(
    os.getenv("ROUTING_PROVIDER", "osrm"),
    os.getenv("OSRM_BASE_URL", "https://router.project-osrm.org"),
    float(os.getenv("ROUTING_TIMEOUT_SECONDS", "2.5")),
    float(os.getenv("ROUTING_CACHE_TTL_SECONDS", "300")),
)

@asynccontextmanager
async def lifespan(_: FastAPI):
    yield
    await planner.close()

app = FastAPI(title="LogiTrack Route Analytics", version="1.0.0", lifespan=lifespan)
configure_tracing()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "UP"}


@app.post("/routes/analyze", response_model=RouteResponse)
async def analyze(request: RouteRequest) -> RouteResponse:
    generated = datetime.now(timezone.utc)
    result = await planner.plan(
        Coordinate(request.origin.lat, request.origin.lon),
        Coordinate(request.destination.lat, request.destination.lon),
    )
    return RouteResponse(
        routeId=uuid.uuid4(), provider=result.provider, algorithmVersion="route-v1",
        coordinates=result.coordinates, distanceMeters=result.distance_meters,
        durationSeconds=result.duration_seconds,
        plannedEta=generated + timedelta(seconds=result.duration_seconds),
        geometryHash=result.geometry_hash, generatedAt=generated,
    )


@app.post("/reports/daily-kpis.pdf")
def daily_kpi_pdf(rows: Annotated[list[DailyKpiRow], Body(min_length=1, max_length=90)]) -> Response:
    return Response(
        content=render_daily_kpi_report(rows),
        media_type="application/pdf",
        headers={"Content-Disposition": "attachment; filename=logitrack-daily-kpi-report.pdf"},
    )
