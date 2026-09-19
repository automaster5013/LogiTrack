package io.logitrack.observability;

import io.logitrack.outbox.*;
import io.logitrack.replay.*;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class RecoveryQueueMetricsTest {
    @Test void publishesRecoveryBacklogsWithoutDatabaseReadsDuringScrape(){
        var outbox=mock(OutboxRepository.class);var deadLetters=mock(DeadLetterEventRepository.class);var registry=new SimpleMeterRegistry();
        when(outbox.countByStatus(OutboxEvent.Status.PENDING)).thenReturn(7L);
        when(outbox.countByStatus(OutboxEvent.Status.FAILED)).thenReturn(2L);
        when(outbox.oldestPendingAgeSeconds()).thenReturn(42.4);
        when(deadLetters.countByStatus(DeadLetterEvent.Status.PENDING)).thenReturn(3L);
        var metrics=new RecoveryQueueMetrics(outbox,deadLetters,registry);metrics.refresh();
        assertEquals(7,registry.get("logitrack.outbox.backlog").tag("status","pending").gauge().value());
        assertEquals(2,registry.get("logitrack.outbox.backlog").tag("status","failed").gauge().value());
        assertEquals(3,registry.get("logitrack.dlq.backlog").gauge().value());
        assertEquals(42,registry.get("logitrack.outbox.oldest.age.seconds").gauge().value());
        verify(outbox,times(2)).countByStatus(any());verify(outbox).oldestPendingAgeSeconds();verify(deadLetters).countByStatus(DeadLetterEvent.Status.PENDING);
    }

    @Test void retainsLastKnownValuesWhenRefreshFails(){
        var outbox=mock(OutboxRepository.class);var deadLetters=mock(DeadLetterEventRepository.class);var registry=new SimpleMeterRegistry();
        when(outbox.countByStatus(OutboxEvent.Status.PENDING)).thenReturn(1L).thenThrow(new IllegalStateException("database offline"));
        when(outbox.countByStatus(OutboxEvent.Status.FAILED)).thenReturn(0L);
        when(outbox.oldestPendingAgeSeconds()).thenReturn(0.0);
        when(deadLetters.countByStatus(DeadLetterEvent.Status.PENDING)).thenReturn(4L);
        var metrics=new RecoveryQueueMetrics(outbox,deadLetters,registry);metrics.refresh();metrics.refresh();metrics.refresh();
        assertEquals(1,registry.get("logitrack.outbox.backlog").tag("status","pending").gauge().value());
        assertEquals(4,registry.get("logitrack.dlq.backlog").gauge().value());
        assertEquals(2,registry.get("logitrack.recovery.metrics.refresh.failures").counter().count());
    }
}
