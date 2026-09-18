package io.logitrack.event;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
import java.util.UUID;

public record EventEnvelope(UUID eventId, String eventType, Instant occurredAt, String traceId, int schemaVersion, JsonNode payload) {}

