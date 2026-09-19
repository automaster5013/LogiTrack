package io.logitrack.maintenance;

import io.logitrack.event.ProcessedEventRepository;
import io.logitrack.outbox.OutboxRepository;
import io.logitrack.telemetry.TelemetryPointRepository;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import java.time.Duration;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class RetentionCleanupTest {
    @Test void deletesBoundedBatchesAndRecordsCounts(){
        var processed=mock(ProcessedEventRepository.class);var outbox=mock(OutboxRepository.class);var telemetry=mock(TelemetryPointRepository.class);var metrics=new SimpleMeterRegistry();
        when(processed.deleteBatchBefore(any(),eq(1000))).thenReturn(3);when(outbox.deletePublishedBatchBefore(any(),eq(1000))).thenReturn(5);when(telemetry.deleteBatchBefore(any(),eq(1000))).thenReturn(7);
        new RetentionCleanup(processed,outbox,telemetry,metrics,Duration.ofDays(30),Duration.ofDays(7),Duration.ofDays(30),1000).cleanup();
        assertEquals(3,metrics.get("logitrack.retention.deleted").tag("table","processed_events").counter().count());
        assertEquals(5,metrics.get("logitrack.retention.deleted").tag("table","outbox_events").counter().count());
        assertEquals(7,metrics.get("logitrack.retention.deleted").tag("table","telemetry_points").counter().count());
    }
    @Test void rejectsUnsafeRetentionConfiguration(){
        var processed=mock(ProcessedEventRepository.class);var outbox=mock(OutboxRepository.class);var telemetry=mock(TelemetryPointRepository.class);var metrics=new SimpleMeterRegistry();
        assertThrows(IllegalArgumentException.class,()->new RetentionCleanup(processed,outbox,telemetry,metrics,Duration.ofHours(23),Duration.ofDays(7),Duration.ofDays(30),1000));
        assertThrows(IllegalArgumentException.class,()->new RetentionCleanup(processed,outbox,telemetry,metrics,Duration.ofDays(30),Duration.ofDays(7),Duration.ofDays(30),10_001));
    }
}
