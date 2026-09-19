package io.logitrack.delivery;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.outbox.*;
import io.logitrack.route.*;
import org.junit.jupiter.api.*;
import org.mockito.ArgumentCaptor;
import java.util.Optional;
import java.util.List;
import java.util.UUID;
import java.time.Instant;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DeliveryServiceTest {
    private final DeliveryRepository deliveries=mock(DeliveryRepository.class);
    private final OutboxRepository outbox=mock(OutboxRepository.class);
    private final RouteAnalysisClient analysis=mock(RouteAnalysisClient.class);
    private final RouteSnapshotRepository routes=mock(RouteSnapshotRepository.class);
    private final DeliveryService service=new DeliveryService(deliveries,outbox,new ObjectMapper().findAndRegisterModules(),analysis,routes);

    @Test void savesDeliveryAndEventToOutbox(){
        when(deliveries.findByIdempotencyKey("key-1")).thenReturn(Optional.empty());
        when(deliveries.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        when(analysis.analyze(any())).thenReturn(route());
        var result=service.create(request(),"key-1","trace-1");
        assertEquals(Delivery.Status.CREATED,result.getStatus());
        var event=ArgumentCaptor.forClass(OutboxEvent.class); verify(outbox).save(event.capture());
        assertEquals("delivery.created.v1",event.getValue().getTopic());
        assertTrue(event.getValue().getPayload().contains(result.getId().toString()));
        assertTrue(event.getValue().getPayload().contains("plannedDurationSeconds"));
        verify(routes).save(any());
    }

    @Test void sameIdempotencyKeyReturnsExistingWithoutAnotherEvent(){
        var existing=Delivery.create(request(),"key-1");
        when(deliveries.findByIdempotencyKey("key-1")).thenReturn(Optional.of(existing));
        assertSame(existing,service.create(request(),"key-1","trace-2"));
        verifyNoInteractions(outbox);
    }

    @Test void rejectsDispatchKeyOwnedByAnotherOrder(){
        var firstOrder=UUID.randomUUID();
        var existing=Delivery.create(request(),"dispatch-key",firstOrder);
        when(deliveries.findByIdempotencyKey("dispatch-key")).thenReturn(Optional.of(existing));

        assertThrows(IllegalStateException.class,()->service.createForOrder(
            UUID.randomUUID(),request(),"dispatch-key","trace-2"));
        verifyNoInteractions(outbox);
    }

    @Test void rejectsInvalidCoordinates(){
        var bad=new CreateDeliveryRequest("ORD-1","TRUCK-1",new CreateDeliveryRequest.Location("X",91,0),request().destination());
        when(deliveries.findByIdempotencyKey("key-1")).thenReturn(Optional.empty());
        assertThrows(IllegalArgumentException.class,()->service.create(bad,"key-1","trace-3"));
    }

    private CreateDeliveryRequest request(){return new CreateDeliveryRequest("ORD-1","TRUCK-1",
        new CreateDeliveryRequest.Location("Seoul",37.5665,126.978),new CreateDeliveryRequest.Location("Incheon",37.4563,126.7052));}
    private RoutePlan route(){var now=Instant.now();return new RoutePlan(UUID.randomUUID(),"test","route-v1",
        List.of(List.of(126.978,37.5665),List.of(126.7052,37.4563)),30000,2400,now.plusSeconds(2400),"hash",now);}
}
