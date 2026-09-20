package io.logitrack.outbox;

import org.junit.jupiter.api.Test;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Duration;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class OutboxPublisherTest {
    @Test void publishesConfiguredBatchAndCountsSuccess() {
        var attempt=mock(OutboxPublishAttempt.class);when(attempt.publishNext(5000)).thenReturn(true,false);
        new OutboxPublisher(attempt,new SimpleMeterRegistry(),20,Duration.ofSeconds(5)).publishPending();
        verify(attempt,times(2)).publishNext(5000);
    }
    @Test void capsWorkAtConfiguredBatchSize(){var attempt=mock(OutboxPublishAttempt.class);when(attempt.publishNext(5000)).thenReturn(true);new OutboxPublisher(attempt,new SimpleMeterRegistry(),3,Duration.ofSeconds(5)).publishPending();verify(attempt,times(3)).publishNext(5000);}
    @Test void recordsFailuresWithoutFloodingTheScheduler(){var attempt=mock(OutboxPublishAttempt.class);var metrics=new SimpleMeterRegistry();when(attempt.publishNext(5000)).thenThrow(new IllegalStateException("database offline")).thenReturn(false);var publisher=new OutboxPublisher(attempt,metrics,20,Duration.ofSeconds(5));assertDoesNotThrow(publisher::publishPending);assertDoesNotThrow(publisher::publishPending);assertEquals(1,metrics.get("logitrack.outbox.publish.failures").counter().count());}
    @Test void rejectsUnsafePublisherConfiguration(){var attempt=mock(OutboxPublishAttempt.class);var metrics=new SimpleMeterRegistry();assertThrows(IllegalArgumentException.class,()->new OutboxPublisher(attempt,metrics,0,Duration.ofSeconds(5)));assertThrows(IllegalArgumentException.class,()->new OutboxPublisher(attempt,metrics,20,Duration.ofSeconds(31)));}
}
