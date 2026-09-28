package io.logitrack.delivery;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;

import java.util.List;
import java.time.Instant;
import java.time.Duration;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

class DemoDeliverySeederTest {
    private final DeliveryRepository deliveries=mock(DeliveryRepository.class);
    private final DeliveryService service=mock(DeliveryService.class);
    private final SimpleMeterRegistry metrics=new SimpleMeterRegistry();

    @Test void replenishesOnlyTheMissingActiveDeliveries(){
        when(deliveries.countFreshDemoActive(any(),any())).thenReturn(10L);
        when(deliveries.deleteCompletedDemoBatchBefore(any(),anyInt())).thenReturn(3);
        new DemoDeliverySeeder(deliveries,service,metrics,12,7200,Duration.ofDays(7),250).replenish();

        var requests=ArgumentCaptor.forClass(CreateDeliveryRequest.class);
        verify(service,times(2)).create(requests.capture(),startsWith("demo-seed-"),startsWith("demo-seeder-"));
        assertEquals(2,requests.getAllValues().stream().map(CreateDeliveryRequest::vehicleId).distinct().count());
        verify(deliveries).countFreshDemoActive(argThat(statuses->statuses.containsAll(
            List.of(Delivery.Status.CREATED,Delivery.Status.IN_TRANSIT,Delivery.Status.DELAYED))),argThat(cutoff->cutoff.isBefore(Instant.now())));
        verify(deliveries).deleteCompletedDemoBatchBefore(argThat(cutoff->cutoff.isBefore(Instant.now())),eq(250));
        assertEquals(3,metrics.get("logitrack.demo.cleanup.deleted").counter().count());
        assertEquals(0,metrics.get("logitrack.demo.cleanup.failures").counter().count());
        assertEquals(true,metrics.get("logitrack.demo.cleanup.last.success.timestamp.seconds").gauge().value()>0);
    }

    @Test void doesNothingWhenTheTargetIsAlreadyMet(){
        when(deliveries.countFreshDemoActive(any(),any())).thenReturn(12L);
        new DemoDeliverySeeder(deliveries,service,metrics,12,7200,Duration.ofDays(7),250).replenish();
        verifyNoInteractions(service);
    }

    @Test void replenishesEvenWhenCompletedDemoCleanupFails(){
        when(deliveries.deleteCompletedDemoBatchBefore(any(),anyInt())).thenThrow(new IllegalStateException("database busy"));
        when(deliveries.countFreshDemoActive(any(),any())).thenReturn(11L);
        new DemoDeliverySeeder(deliveries,service,metrics,12,7200,Duration.ofDays(7),250).replenish();
        verify(service).create(any(),startsWith("demo-seed-"),startsWith("demo-seeder-"));
        assertEquals(1,metrics.get("logitrack.demo.cleanup.failures").counter().count());
        assertEquals(0,metrics.get("logitrack.demo.cleanup.last.success.timestamp.seconds").gauge().value());
    }

    @Test void rejectsUnsafeTargets(){
        assertThrows(IllegalArgumentException.class,()->new DemoDeliverySeeder(deliveries,service,metrics,0,7200,Duration.ofDays(7),250));
        assertThrows(IllegalArgumentException.class,()->new DemoDeliverySeeder(deliveries,service,metrics,51,7200,Duration.ofDays(7),250));
        assertThrows(IllegalArgumentException.class,()->new DemoDeliverySeeder(deliveries,service,metrics,12,59,Duration.ofDays(7),250));
        assertThrows(IllegalArgumentException.class,()->new DemoDeliverySeeder(deliveries,service,metrics,12,86401,Duration.ofDays(7),250));
        assertThrows(IllegalArgumentException.class,()->new DemoDeliverySeeder(deliveries,service,metrics,12,7200,Duration.ofMinutes(9),250));
        assertThrows(IllegalArgumentException.class,()->new DemoDeliverySeeder(deliveries,service,metrics,12,7200,Duration.ofDays(91),250));
        assertThrows(IllegalArgumentException.class,()->new DemoDeliverySeeder(deliveries,service,metrics,12,7200,Duration.ofDays(7),0));
        assertThrows(IllegalArgumentException.class,()->new DemoDeliverySeeder(deliveries,service,metrics,12,7200,Duration.ofDays(7),1001));
    }
}
