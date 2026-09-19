package io.logitrack.outbox;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.kafka.core.KafkaTemplate;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class OutboxPublishAttemptTest {
    @Test void publishesOneLockedEventAndCountsSuccess(){
        var repository=mock(OutboxRepository.class);var kafka=mock(KafkaTemplate.class);var metrics=new SimpleMeterRegistry();var event=event();
        when(repository.lockNextPending()).thenReturn(Optional.of(event));when(kafka.send(anyString(),any(),any())).thenReturn(CompletableFuture.completedFuture(null));
        assertTrue(new OutboxPublishAttempt(repository,kafka,metrics).publishNext(5000));
        assertEquals(OutboxEvent.Status.PUBLISHED,event.getStatus());assertEquals(1,metrics.get("logitrack.outbox.published").counter().count());
    }
    @Test void stopsWhenNoDueEventExists(){var repository=mock(OutboxRepository.class);when(repository.lockNextPending()).thenReturn(Optional.empty());assertFalse(new OutboxPublishAttempt(repository,mock(KafkaTemplate.class),new SimpleMeterRegistry()).publishNext(5000));}
    @Test void recordsOneFailureWithoutThrowingIntoTheBatch(){
        var repository=mock(OutboxRepository.class);var kafka=mock(KafkaTemplate.class);var metrics=new SimpleMeterRegistry();var event=event();
        when(repository.lockNextPending()).thenReturn(Optional.of(event));when(kafka.send(anyString(),any(),any())).thenReturn(CompletableFuture.failedFuture(new IllegalStateException("broker offline")));
        assertTrue(new OutboxPublishAttempt(repository,kafka,metrics).publishNext(5000));
        assertEquals(OutboxEvent.Status.PENDING,event.getStatus());assertEquals(1,event.getAttempts());assertEquals(1,metrics.get("logitrack.outbox.failures").counter().count());
    }
    private OutboxEvent event(){return new OutboxEvent(UUID.randomUUID(),"DELIVERY",UUID.randomUUID(),"delivery.created.v1","delivery.created.v1","key","{}");}
}
