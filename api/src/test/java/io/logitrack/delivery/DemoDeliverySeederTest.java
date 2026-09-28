package io.logitrack.delivery;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

class DemoDeliverySeederTest {
    private final DeliveryRepository deliveries=mock(DeliveryRepository.class);
    private final DeliveryService service=mock(DeliveryService.class);

    @Test void replenishesOnlyTheMissingActiveDeliveries(){
        when(deliveries.countByStatusIn(any())).thenReturn(10L);
        new DemoDeliverySeeder(deliveries,service,12).replenish();

        var requests=ArgumentCaptor.forClass(CreateDeliveryRequest.class);
        verify(service,times(2)).create(requests.capture(),startsWith("demo-seed-"),startsWith("demo-seeder-"));
        assertEquals(2,requests.getAllValues().stream().map(CreateDeliveryRequest::vehicleId).distinct().count());
        verify(deliveries).countByStatusIn(argThat(statuses->statuses.containsAll(
            List.of(Delivery.Status.CREATED,Delivery.Status.IN_TRANSIT,Delivery.Status.DELAYED))));
    }

    @Test void doesNothingWhenTheTargetIsAlreadyMet(){
        when(deliveries.countByStatusIn(any())).thenReturn(12L);
        new DemoDeliverySeeder(deliveries,service,12).replenish();
        verifyNoInteractions(service);
    }

    @Test void rejectsUnsafeTargets(){
        assertThrows(IllegalArgumentException.class,()->new DemoDeliverySeeder(deliveries,service,0));
        assertThrows(IllegalArgumentException.class,()->new DemoDeliverySeeder(deliveries,service,51));
    }
}
