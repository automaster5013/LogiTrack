package io.logitrack.alert;

import org.junit.jupiter.api.Test;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

class DeliveryAlertTest {
    @Test void severityOnlyEscalatesWhileAlertIsActive() {
        var alert=new DeliveryAlert(UUID.randomUUID(),DeliveryAlert.Type.DELAY,DeliveryAlert.Severity.WARNING,"late",700,600);
        assertTrue(alert.observe(DeliveryAlert.Severity.CRITICAL,"very late",2000));
        assertFalse(alert.observe(DeliveryAlert.Severity.WARNING,"less late",800));
        assertEquals(DeliveryAlert.Severity.CRITICAL,alert.getSeverity());
        assertEquals(3,alert.getOccurrenceCount());
    }

    @Test void resolutionCapturesFinalObservation() {
        var alert=new DeliveryAlert(UUID.randomUUID(),DeliveryAlert.Type.ROUTE_DEVIATION,
            DeliveryAlert.Severity.WARNING,"off route",850,500);

        alert.resolve(120);

        assertEquals(DeliveryAlert.Status.RESOLVED,alert.getStatus());
        assertEquals(120,alert.getObservedValue());
        assertNotNull(alert.getResolvedAt());
        assertEquals(alert.getLastObservedAt(),alert.getResolvedAt());
    }

    @Test void activeAlertAcknowledgementIsImmutableAndIdempotent() {
        var alert=new DeliveryAlert(UUID.randomUUID(),DeliveryAlert.Type.DELAY,
            DeliveryAlert.Severity.WARNING,"late",700,600);

        assertTrue(alert.acknowledge("  control-tower  "));
        var acknowledgedAt=alert.getAcknowledgedAt();
        assertFalse(alert.acknowledge("another-operator"));

        assertEquals("control-tower",alert.getAcknowledgedBy());
        assertEquals(acknowledgedAt,alert.getAcknowledgedAt());
    }

    @Test void resolvedAlertCannotBeAcknowledged() {
        var alert=new DeliveryAlert(UUID.randomUUID(),DeliveryAlert.Type.DELAY,
            DeliveryAlert.Severity.WARNING,"late",700,600);
        alert.resolve(0);
        assertThrows(IllegalStateException.class,()->alert.acknowledge("control-tower"));
    }

    @Test void acknowledgementRequiresAnOperator() {
        var alert=new DeliveryAlert(UUID.randomUUID(),DeliveryAlert.Type.DELAY,
            DeliveryAlert.Severity.WARNING,"late",700,600);
        assertThrows(IllegalArgumentException.class,()->alert.acknowledge("  "));
    }
}
