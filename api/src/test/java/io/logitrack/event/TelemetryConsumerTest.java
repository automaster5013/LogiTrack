package io.logitrack.event;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.alert.AlertService;
import io.logitrack.delivery.*;
import io.logitrack.order.OrderService;
import io.logitrack.stream.CommittedDeliveryStream;
import io.logitrack.telemetry.*;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.util.*;
import java.time.Duration;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class TelemetryConsumerTest {
    @Test void rejectsNegativeFutureSkew(){assertThrows(IllegalArgumentException.class,()->new TelemetryConsumer(new ObjectMapper(),mock(DeliveryRepository.class),mock(ProcessedEventRepository.class),mock(CommittedDeliveryStream.class),mock(AlertService.class),mock(OrderService.class),mock(TelemetryPointRepository.class),Duration.ofSeconds(-1),new SimpleMeterRegistry()));}
    @Test void persistsImmutablePointWithDeliveryUpdate() throws Exception {
        var deliveries=mock(DeliveryRepository.class);var processed=mock(ProcessedEventRepository.class);
        var stream=mock(CommittedDeliveryStream.class);var alerts=mock(AlertService.class);var orders=mock(OrderService.class);var points=mock(TelemetryPointRepository.class);
        var delivery=Delivery.create(request(),"key");var eventId=UUID.randomUUID();
        when(deliveries.findById(delivery.getId())).thenReturn(Optional.of(delivery));
        when(points.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        var metrics=new SimpleMeterRegistry();var consumer=new TelemetryConsumer(new ObjectMapper().findAndRegisterModules(),deliveries,processed,stream,alerts,orders,points,Duration.ofMinutes(5),metrics);
        consumer.consume("{\"eventId\":\""+eventId+"\",\"eventType\":\"vehicle.telemetry.v1\",\"schemaVersion\":1,\"occurredAt\":\"2026-09-19T10:00:00Z\",\"payload\":{"+
            "\"deliveryId\":\""+delivery.getId()+"\",\"vehicleId\":\"TRUCK-1\",\"lat\":37.5,\"lon\":126.9,\"progress\":0.25,\"status\":\"IN_TRANSIT\",\"eta\":null}}");
        var saved=ArgumentCaptor.forClass(TelemetryPoint.class);verify(points).save(saved.capture());
        assertEquals(eventId,saved.getValue().getEventId());assertEquals(delivery.getId(),saved.getValue().getDeliveryId());
        assertEquals(37.5,saved.getValue().getLatitude());assertEquals(0.25,delivery.getProgress());
        verify(processed).save(any());verify(stream).publishDelivery(delivery);verify(stream).publishTelemetry(saved.getValue());
        assertEquals(1,metrics.get("logitrack.telemetry.events").tag("outcome","applied").counter().count());
        var trace=ArgumentCaptor.forClass(String.class);verify(alerts).evaluate(eq(delivery),trace.capture());verify(orders).fulfillFromDelivery(eq(delivery),trace.capture());assertEquals(trace.getAllValues().get(0),trace.getAllValues().get(1));assertDoesNotThrow(()->UUID.fromString(trace.getValue()));
    }

    @Test void duplicateEventDoesNotAppendPoint() throws Exception {
        var processed=mock(ProcessedEventRepository.class);when(processed.existsById(any())).thenReturn(true);var points=mock(TelemetryPointRepository.class);
        var consumer=new TelemetryConsumer(new ObjectMapper(),mock(DeliveryRepository.class),processed,mock(CommittedDeliveryStream.class),mock(AlertService.class),mock(OrderService.class),points,Duration.ofMinutes(5),new SimpleMeterRegistry());
        consumer.consume("{\"eventId\":\""+UUID.randomUUID()+"\"}");
        verifyNoInteractions(points);
    }

    @Test void rejectsStringEncodedNumbersBeforeMutation() {
        var deliveries=mock(DeliveryRepository.class);var processed=mock(ProcessedEventRepository.class);var points=mock(TelemetryPointRepository.class);
        var delivery=Delivery.create(request(),"key");var eventId=UUID.randomUUID();
        when(deliveries.findById(delivery.getId())).thenReturn(Optional.of(delivery));
        var consumer=new TelemetryConsumer(new ObjectMapper(),deliveries,processed,mock(CommittedDeliveryStream.class),mock(AlertService.class),mock(OrderService.class),points,Duration.ofMinutes(5),new SimpleMeterRegistry());
        var raw="{\"eventId\":\""+eventId+"\",\"eventType\":\"vehicle.telemetry.v1\",\"schemaVersion\":1,\"occurredAt\":\"2026-09-19T10:00:00Z\",\"payload\":{"+
            "\"deliveryId\":\""+delivery.getId()+"\",\"vehicleId\":\"TRUCK-1\",\"lat\":\"37.5\",\"lon\":126.9,\"progress\":0.25,\"status\":\"IN_TRANSIT\"}}";
        assertThrows(IllegalArgumentException.class,()->consumer.consume(raw));
        assertEquals(Delivery.Status.CREATED,delivery.getStatus());verifyNoInteractions(points);verify(processed,never()).save(any());
    }

    @Test void storesLateHistoryWithoutRegressingCurrentState() throws Exception {
        var deliveries=mock(DeliveryRepository.class);var processed=mock(ProcessedEventRepository.class);var stream=mock(CommittedDeliveryStream.class);var alerts=mock(AlertService.class);var orders=mock(OrderService.class);var points=mock(TelemetryPointRepository.class);
        var delivery=Delivery.create(request(),"key");delivery.applyTelemetry(37.5,126.9,0.8,null,Delivery.Status.IN_TRANSIT,java.time.Instant.parse("2026-09-19T11:00:00Z"));var eventId=UUID.randomUUID();
        when(deliveries.findById(delivery.getId())).thenReturn(Optional.of(delivery));
        when(points.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        var metrics=new SimpleMeterRegistry();var consumer=new TelemetryConsumer(new ObjectMapper(),deliveries,processed,stream,alerts,orders,points,Duration.ofMinutes(5),metrics);
        consumer.consume("{\"eventId\":\""+eventId+"\",\"eventType\":\"vehicle.telemetry.v1\",\"schemaVersion\":1,\"occurredAt\":\"2026-09-19T10:00:00Z\",\"payload\":{"+
            "\"deliveryId\":\""+delivery.getId()+"\",\"vehicleId\":\"TRUCK-1\",\"lat\":37.4,\"lon\":126.8,\"progress\":0.2,\"status\":\"DELAYED\"}}" );
        assertEquals(0.8,delivery.getProgress());assertEquals(Delivery.Status.IN_TRANSIT,delivery.getStatus());
        verify(points).save(any());verify(processed).save(any());verify(stream).publishTelemetry(any());verify(stream,never()).publishDelivery(any());verifyNoInteractions(alerts,orders);
        assertEquals(1,metrics.get("logitrack.telemetry.events").tag("outcome","stale").counter().count());
    }

    @Test void rejectsMismatchedVehicleAndFarFutureTimestamp() {
        var deliveries=mock(DeliveryRepository.class);var processed=mock(ProcessedEventRepository.class);var points=mock(TelemetryPointRepository.class);var delivery=Delivery.create(request(),"key");
        when(deliveries.findById(delivery.getId())).thenReturn(Optional.of(delivery));
        var consumer=new TelemetryConsumer(new ObjectMapper(),deliveries,processed,mock(CommittedDeliveryStream.class),mock(AlertService.class),mock(OrderService.class),points,Duration.ofMinutes(5),new SimpleMeterRegistry());
        var base="{\"eventId\":\"%s\",\"eventType\":\"vehicle.telemetry.v1\",\"schemaVersion\":1,\"occurredAt\":\"%s\",\"payload\":{\"deliveryId\":\"%s\",\"vehicleId\":\"%s\",\"lat\":37.5,\"lon\":126.9,\"progress\":0.2,\"status\":\"IN_TRANSIT\"}}";
        assertThrows(IllegalArgumentException.class,()->consumer.consume(base.formatted(UUID.randomUUID(),java.time.Instant.now(),delivery.getId(),"OTHER")));
        assertThrows(IllegalArgumentException.class,()->consumer.consume(base.formatted(UUID.randomUUID(),java.time.Instant.now().plus(Duration.ofMinutes(10)),delivery.getId(),"TRUCK-1")));
        verifyNoInteractions(points);verify(processed,never()).save(any());
    }

    @Test void rejectsUnsafeTraceIdBeforeDeliveryLookup(){var deliveries=mock(DeliveryRepository.class);var consumer=new TelemetryConsumer(new ObjectMapper(),deliveries,mock(ProcessedEventRepository.class),mock(CommittedDeliveryStream.class),mock(AlertService.class),mock(OrderService.class),mock(TelemetryPointRepository.class),Duration.ofMinutes(5),new SimpleMeterRegistry());var raw="{\"eventId\":\""+UUID.randomUUID()+"\",\"eventType\":\"vehicle.telemetry.v1\",\"schemaVersion\":1,\"traceId\":\"bad trace\",\"payload\":{}}";assertThrows(IllegalArgumentException.class,()->consumer.consume(raw));verifyNoInteractions(deliveries);}

    private CreateDeliveryRequest request(){return new CreateDeliveryRequest("ORD-1","TRUCK-1",new CreateDeliveryRequest.Location("Seoul",37.5665,126.978),new CreateDeliveryRequest.Location("Incheon",37.4563,126.7052));}
}
