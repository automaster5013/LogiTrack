package io.logitrack.outbox;

import org.junit.jupiter.api.Test;
import java.time.Duration;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class OutboxPublisherTest {
    @Test void publishesConfiguredBatchAndCountsSuccess() {
        var attempt=mock(OutboxPublishAttempt.class);when(attempt.publishNext(5000)).thenReturn(true,false);
        new OutboxPublisher(attempt,20,Duration.ofSeconds(5)).publishPending();
        verify(attempt,times(2)).publishNext(5000);
    }
    @Test void capsWorkAtConfiguredBatchSize(){var attempt=mock(OutboxPublishAttempt.class);when(attempt.publishNext(5000)).thenReturn(true);new OutboxPublisher(attempt,3,Duration.ofSeconds(5)).publishPending();verify(attempt,times(3)).publishNext(5000);}
    @Test void rejectsUnsafePublisherConfiguration(){var attempt=mock(OutboxPublishAttempt.class);assertThrows(IllegalArgumentException.class,()->new OutboxPublisher(attempt,0,Duration.ofSeconds(5)));assertThrows(IllegalArgumentException.class,()->new OutboxPublisher(attempt,20,Duration.ofSeconds(31)));}
}
