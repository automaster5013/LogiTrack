package io.logitrack.route;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record RoutePlan(UUID routeId, String provider, String algorithmVersion,
    List<List<Double>> coordinates, long distanceMeters, long durationSeconds,
    Instant plannedEta, String geometryHash, Instant generatedAt) {}

