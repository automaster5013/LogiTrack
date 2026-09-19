package io.logitrack.delivery;

import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertEquals;

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

    private CreateDeliveryRequest request() {
        return new CreateDeliveryRequest(
            "ORD-TERMINAL",
            "TRUCK-TERMINAL",
            new CreateDeliveryRequest.Location("Seoul", 37.5665, 126.978),
            new CreateDeliveryRequest.Location("Incheon", 37.4563, 126.7052)
        );
    }
}
