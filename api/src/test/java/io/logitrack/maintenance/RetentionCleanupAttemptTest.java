package io.logitrack.maintenance;

import io.logitrack.event.ProcessedEventRepository;
import io.logitrack.outbox.OutboxRepository;
import io.logitrack.telemetry.TelemetryPointRepository;
import org.junit.jupiter.api.Test;
import java.time.Instant;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class RetentionCleanupAttemptTest {
    @Test void returnsEachCommittedDeletionCount(){
        var processed=mock(ProcessedEventRepository.class);var outbox=mock(OutboxRepository.class);var telemetry=mock(TelemetryPointRepository.class);
        when(processed.deleteBatchBefore(any(),eq(50))).thenReturn(2);when(outbox.deletePublishedBatchBefore(any(),eq(50))).thenReturn(3);when(telemetry.deleteBatchBefore(any(),eq(50))).thenReturn(4);
        var result=new RetentionCleanupAttempt(processed,outbox,telemetry).cleanup(Instant.EPOCH,Instant.EPOCH,Instant.EPOCH,50);
        assertEquals(new RetentionCleanupAttempt.Result(2,3,4),result);
    }
}
