package io.logitrack.order;

import io.logitrack.delivery.Delivery;
import java.time.Instant;
import java.util.UUID;

public record OrderSummary(
    UUID id,
    String orderNumber,
    CustomerOrder.Status status,
    String originName,
    double originLat,
    double originLon,
    String destinationName,
    double destinationLat,
    double destinationLon,
    UUID deliveryId,
    String vehicleId,
    Delivery.Status deliveryStatus,
    Instant createdAt,
    Instant updatedAt
) {}
