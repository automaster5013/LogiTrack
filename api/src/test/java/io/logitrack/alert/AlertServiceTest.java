package io.logitrack.alert;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.outbox.*;
import io.logitrack.route.RouteSnapshotRepository;
import io.logitrack.stream.CommittedDeliveryStream;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AlertServiceTest {
    private final DeliveryAlertRepository alerts=mock(DeliveryAlertRepository.class);
    private final OutboxRepository outbox=mock(OutboxRepository.class);
    private final CommittedDeliveryStream stream=mock(CommittedDeliveryStream.class);
    private final AlertPolicyService policies=mock(AlertPolicyService.class);
    private final AlertService service=new AlertService(alerts,mock(RouteSnapshotRepository.class),outbox,
        new ObjectMapper().findAndRegisterModules(),stream,policies);

    @Test void acknowledgementEmitsOneAuditableEventAndIsIdempotent() {
        var alert=new DeliveryAlert(UUID.randomUUID(),DeliveryAlert.Type.ROUTE_DEVIATION,
            DeliveryAlert.Severity.CRITICAL,"off route",1800,500);
        when(alerts.findByIdForUpdate(alert.getId())).thenReturn(Optional.of(alert));

        assertSame(alert,service.acknowledge(alert.getId(),"operator-a","trace-a"));
        assertSame(alert,service.acknowledge(alert.getId(),"operator-a","trace-b"));

        var event=ArgumentCaptor.forClass(OutboxEvent.class);
        verify(outbox,times(1)).save(event.capture());
        assertTrue(event.getValue().getPayload().contains("ACKNOWLEDGED"));
        assertTrue(event.getValue().getPayload().contains("operator-a"));
        verify(stream,times(1)).publishAlert(alert);
    }

    @Test void keyedAcknowledgementReturnsOnlyTheMatchingStoredRequest() {
        var alert=new DeliveryAlert(UUID.randomUUID(),DeliveryAlert.Type.ROUTE_DEVIATION,
            DeliveryAlert.Severity.CRITICAL,"off route",1800,500);
        when(alerts.findByAcknowledgementRequestKey("request-key")).thenReturn(Optional.empty(),Optional.of(alert));
        when(alerts.findByIdForUpdate(alert.getId())).thenReturn(Optional.of(alert));

        assertSame(alert,service.acknowledge(alert.getId(),"operator-a","trace-a","request-key"));
        assertSame(alert,service.acknowledge(alert.getId(),"operator-a","trace-b","request-key"));
        assertEquals("request-key",alert.getAcknowledgementRequestKey());
        assertFalse(new ObjectMapper().findAndRegisterModules().valueToTree(alert).has("acknowledgementRequestKey"));
        verify(alerts,times(2)).lockAcknowledgementRequestKey("request-key");
        verify(outbox,times(1)).save(any());
        assertThrows(IllegalStateException.class,()->service.acknowledge(UUID.randomUUID(),"operator-a","trace","request-key"));
        assertThrows(IllegalStateException.class,()->service.acknowledge(alert.getId(),"operator-b","trace","request-key"));
    }

    @Test void newKeyCannotClaimAnAlreadyAcknowledgedAlert() {
        var alert=new DeliveryAlert(UUID.randomUUID(),DeliveryAlert.Type.DELAY,
            DeliveryAlert.Severity.WARNING,"late",700,600);
        alert.acknowledge("operator-a");
        when(alerts.findByAcknowledgementRequestKey("new-key")).thenReturn(Optional.empty());
        when(alerts.findByIdForUpdate(alert.getId())).thenReturn(Optional.of(alert));
        assertThrows(IllegalStateException.class,()->service.acknowledge(alert.getId(),"operator-a","trace","new-key"));
        verifyNoInteractions(outbox);
    }

    @Test void missingAlertReturnsNotFoundSignal() {
        var id=UUID.randomUUID();when(alerts.findByIdForUpdate(id)).thenReturn(Optional.empty());
        assertThrows(NoSuchElementException.class,()->service.acknowledge(id,"operator","trace"));
    }

    @Test void invalidOperatorIsRejectedBeforeLocking() {
        assertThrows(IllegalArgumentException.class,()->service.acknowledge(UUID.randomUUID(),"  ","trace"));
        verifyNoInteractions(alerts);
    }
}
