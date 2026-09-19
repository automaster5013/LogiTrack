package io.logitrack.outbox;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.kafka.core.KafkaTemplate;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class OutboxPublisherTest {
    @Test void publishesConfiguredBatchAndCountsSuccess() {
        var repository=mock(OutboxRepository.class);var kafka=mock(KafkaTemplate.class);var metrics=new SimpleMeterRegistry();var event=event();
        when(repository.lockPendingBatch(20)).thenReturn(List.of(event));when(kafka.send(anyString(),any(),any())).thenReturn(CompletableFuture.completedFuture(null));
        new OutboxPublisher(repository,kafka,metrics,20,Duration.ofSeconds(5)).publishPending();
        assertEquals(OutboxEvent.Status.PUBLISHED,event.getStatus());assertEquals(1,metrics.get("logitrack.outbox.published").counter().count());verify(repository).lockPendingBatch(20);
    }
    @Test void rejectsUnsafePublisherConfiguration(){var repository=mock(OutboxRepository.class);var kafka=mock(KafkaTemplate.class);var metrics=new SimpleMeterRegistry();assertThrows(IllegalArgumentException.class,()->new OutboxPublisher(repository,kafka,metrics,0,Duration.ofSeconds(5)));assertThrows(IllegalArgumentException.class,()->new OutboxPublisher(repository,kafka,metrics,20,Duration.ofSeconds(31)));}
    private OutboxEvent event(){return new OutboxEvent(UUID.randomUUID(),"DELIVERY",UUID.randomUUID(),"delivery.created.v1","delivery.created.v1","key","{}");}
}
