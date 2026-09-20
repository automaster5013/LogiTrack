package io.logitrack.maintenance;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import java.time.Duration;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class RetentionCleanupTest {
    @Test void deletesBoundedBatchesAndRecordsCounts(){
        var attempt=mock(RetentionCleanupAttempt.class);var metrics=new SimpleMeterRegistry();
        when(attempt.cleanup(any(),any(),any(),any(),eq(1000))).thenReturn(new RetentionCleanupAttempt.Result(3,5,7,11));
        new RetentionCleanup(attempt,metrics,Duration.ofDays(30),Duration.ofDays(7),Duration.ofDays(30),Duration.ofDays(90),1000).cleanup();
        assertEquals(3,metrics.get("logitrack.retention.deleted").tag("table","processed_events").counter().count());
        assertEquals(5,metrics.get("logitrack.retention.deleted").tag("table","outbox_events").counter().count());
        assertEquals(7,metrics.get("logitrack.retention.deleted").tag("table","telemetry_points").counter().count());
        assertEquals(11,metrics.get("logitrack.retention.deleted").tag("table","dead_letter_events").counter().count());
    }
    @Test void recordsRepeatedFailuresWithoutThrowingOrClaimingRolledBackDeletes(){
        var attempt=mock(RetentionCleanupAttempt.class);var metrics=new SimpleMeterRegistry();when(attempt.cleanup(any(),any(),any(),any(),anyInt())).thenThrow(new IllegalStateException("database offline"));
        var cleanup=new RetentionCleanup(attempt,metrics,Duration.ofDays(30),Duration.ofDays(7),Duration.ofDays(30),Duration.ofDays(90),1000);
        assertDoesNotThrow(cleanup::cleanup);assertDoesNotThrow(cleanup::cleanup);
        assertEquals(2,metrics.get("logitrack.retention.failures").counter().count());
        assertEquals(0,metrics.get("logitrack.retention.deleted").tag("table","processed_events").counter().count());
    }
    @Test void resumesDeletionAccountingAfterRecovery(){
        var attempt=mock(RetentionCleanupAttempt.class);var metrics=new SimpleMeterRegistry();
        when(attempt.cleanup(any(),any(),any(),any(),anyInt())).thenThrow(new IllegalStateException("database offline"))
            .thenReturn(new RetentionCleanupAttempt.Result(1,2,3,4));
        var cleanup=new RetentionCleanup(attempt,metrics,Duration.ofDays(30),Duration.ofDays(7),Duration.ofDays(30),Duration.ofDays(90),1000);
        cleanup.cleanup();cleanup.cleanup();
        assertEquals(1,metrics.get("logitrack.retention.failures").counter().count());
        assertEquals(3,metrics.get("logitrack.retention.deleted").tag("table","telemetry_points").counter().count());
    }
    @Test void rejectsUnsafeRetentionConfiguration(){
        var attempt=mock(RetentionCleanupAttempt.class);var metrics=new SimpleMeterRegistry();
        assertThrows(IllegalArgumentException.class,()->new RetentionCleanup(attempt,metrics,Duration.ofHours(23),Duration.ofDays(7),Duration.ofDays(30),Duration.ofDays(90),1000));
        assertThrows(IllegalArgumentException.class,()->new RetentionCleanup(attempt,metrics,Duration.ofDays(30),Duration.ofDays(7),Duration.ofDays(30),Duration.ofDays(90),10_001));
    }
}
