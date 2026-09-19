package io.logitrack.delivery;

import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.*;

class DeliveryTest {
    @Test
    void deliveredStateIsTerminalWhenLateTelemetryArrives() {
        var delivery = Delivery.create(request(), "delivery-terminal");
        delivery.applyTelemetry(37.4563, 126.7052, 1, null, Delivery.Status.DELIVERED);

        delivery.applyTelemetry(37.55, 126.95, 0.2, Instant.now().plusSeconds(600), Delivery.Status.IN_TRANSIT);

        assertEquals(Delivery.Status.DELIVERED, delivery.getStatus());
        assertEquals(1, delivery.getProgress());
        assertEquals(37.4563, delivery.getCurrentLat());
        assertEquals(126.7052, delivery.getCurrentLon());
    }

    @Test
    void rejectsInvalidTelemetryWithoutMutatingState() {
        var delivery = Delivery.create(request(), "delivery-invalid");

        assertThrows(IllegalArgumentException.class, () -> delivery.applyTelemetry(Double.NaN, 126.9, 0.2, null, Delivery.Status.IN_TRANSIT));
        assertThrows(IllegalArgumentException.class, () -> delivery.applyTelemetry(37.5, 126.9, 1.01, null, Delivery.Status.IN_TRANSIT));

        assertEquals(Delivery.Status.CREATED, delivery.getStatus());
        assertEquals(0, delivery.getProgress());
        assertEquals(delivery.getOriginLat(), delivery.getCurrentLat());
    }

    private CreateDeliveryRequest request() {
        return new CreateDeliveryRequest(
            "ORD-TERMINAL",
            "TRUCK-TERMINAL",
            new CreateDeliveryRequest.Location("Seoul", 37.5665, 126.978),
            new CreateDeliveryRequest.Location("Incheon", 37.4563, 126.7052)
        );
    }
}
