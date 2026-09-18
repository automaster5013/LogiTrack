package io.logitrack.delivery;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.outbox.*;
import org.junit.jupiter.api.*;
import org.mockito.ArgumentCaptor;
import java.util.Optional;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DeliveryServiceTest {
    private final DeliveryRepository deliveries=mock(DeliveryRepository.class);
    private final OutboxRepository outbox=mock(OutboxRepository.class);
    private final DeliveryService service=new DeliveryService(deliveries,outbox,new ObjectMapper().findAndRegisterModules());

    @Test void savesDeliveryAndEventToOutbox(){
        when(deliveries.findByIdempotencyKey("key-1")).thenReturn(Optional.empty());
        when(deliveries.save(any())).thenAnswer(invocation->invocation.getArgument(0));
        var result=service.create(request(),"key-1","trace-1");
        assertEquals(Delivery.Status.CREATED,result.getStatus());
        var event=ArgumentCaptor.forClass(OutboxEvent.class); verify(outbox).save(event.capture());
        assertEquals("delivery.created.v1",event.getValue().getTopic());
        assertTrue(event.getValue().getPayload().contains(result.getId().toString()));
    }

    @Test void sameIdempotencyKeyReturnsExistingWithoutAnotherEvent(){
        var existing=Delivery.create(request(),"key-1");
        when(deliveries.findByIdempotencyKey("key-1")).thenReturn(Optional.of(existing));
        assertSame(existing,service.create(request(),"key-1","trace-2"));
        verifyNoInteractions(outbox);
    }

    @Test void rejectsInvalidCoordinates(){
        var bad=new CreateDeliveryRequest("ORD-1","TRUCK-1",new CreateDeliveryRequest.Location("X",91,0),request().destination());
        when(deliveries.findByIdempotencyKey("key-1")).thenReturn(Optional.empty());
        assertThrows(IllegalArgumentException.class,()->service.create(bad,"key-1","trace-3"));
    }

    private CreateDeliveryRequest request(){return new CreateDeliveryRequest("ORD-1","TRUCK-1",
        new CreateDeliveryRequest.Location("Seoul",37.5665,126.978),new CreateDeliveryRequest.Location("Incheon",37.4563,126.7052));}
}
