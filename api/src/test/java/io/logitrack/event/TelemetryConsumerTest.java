package io.logitrack.event;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.alert.AlertService;
import io.logitrack.delivery.*;
import io.logitrack.order.OrderService;
import io.logitrack.stream.DeliveryStream;
import io.logitrack.telemetry.*;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class TelemetryConsumerTest {
    @Test void persistsImmutablePointWithDeliveryUpdate() throws Exception {
        var deliveries=mock(DeliveryRepository.class);var processed=mock(ProcessedEventRepository.class);
        var stream=mock(DeliveryStream.class);var alerts=mock(AlertService.class);var orders=mock(OrderService.class);var points=mock(TelemetryPointRepository.class);
        var delivery=Delivery.create(request(),"key");var eventId=UUID.randomUUID();
        when(deliveries.findById(delivery.getId())).thenReturn(Optional.of(delivery));
        var consumer=new TelemetryConsumer(new ObjectMapper().findAndRegisterModules(),deliveries,processed,stream,alerts,orders,points);
        consumer.consume("{\"eventId\":\""+eventId+"\",\"occurredAt\":\"2026-09-19T10:00:00Z\",\"payload\":{"+
            "\"deliveryId\":\""+delivery.getId()+"\",\"lat\":37.5,\"lon\":126.9,\"progress\":0.25,\"status\":\"IN_TRANSIT\",\"eta\":null}}");
        var saved=ArgumentCaptor.forClass(TelemetryPoint.class);verify(points).save(saved.capture());
        assertEquals(eventId,saved.getValue().getEventId());assertEquals(delivery.getId(),saved.getValue().getDeliveryId());
        assertEquals(37.5,saved.getValue().getLatitude());assertEquals(0.25,delivery.getProgress());
        verify(processed).save(any());verify(stream).publish(delivery);
    }

    @Test void duplicateEventDoesNotAppendPoint() throws Exception {
        var processed=mock(ProcessedEventRepository.class);when(processed.existsById(any())).thenReturn(true);var points=mock(TelemetryPointRepository.class);
        var consumer=new TelemetryConsumer(new ObjectMapper(),mock(DeliveryRepository.class),processed,mock(DeliveryStream.class),mock(AlertService.class),mock(OrderService.class),points);
        consumer.consume("{\"eventId\":\""+UUID.randomUUID()+"\"}");
        verifyNoInteractions(points);
    }

    private CreateDeliveryRequest request(){return new CreateDeliveryRequest("ORD-1","TRUCK-1",new CreateDeliveryRequest.Location("Seoul",37.5665,126.978),new CreateDeliveryRequest.Location("Incheon",37.4563,126.7052));}
}
