package io.logitrack.maintenance;

import io.logitrack.event.ProcessedEventRepository;
import io.logitrack.outbox.OutboxRepository;
import io.logitrack.telemetry.TelemetryPointRepository;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import java.time.Instant;

@Component
public class RetentionCleanupAttempt {
    private final ProcessedEventRepository processed;
    private final OutboxRepository outbox;
    private final TelemetryPointRepository telemetry;

    public RetentionCleanupAttempt(ProcessedEventRepository processed,OutboxRepository outbox,TelemetryPointRepository telemetry){this.processed=processed;this.outbox=outbox;this.telemetry=telemetry;}

    @Transactional
    public Result cleanup(Instant processedBefore,Instant outboxBefore,Instant telemetryBefore,int batchSize){
        return new Result(processed.deleteBatchBefore(processedBefore,batchSize),outbox.deletePublishedBatchBefore(outboxBefore,batchSize),telemetry.deleteBatchBefore(telemetryBefore,batchSize));
    }

    public record Result(int processedEvents,int outboxEvents,int telemetryPoints) {}
}
