package io.logitrack.maintenance;

import io.logitrack.event.ProcessedEventRepository;
import io.logitrack.outbox.OutboxRepository;
import io.logitrack.telemetry.TelemetryPointRepository;
import io.logitrack.replay.DeadLetterEventRepository;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import java.time.Instant;

@Component
public class RetentionCleanupAttempt {
    private final ProcessedEventRepository processed;
    private final OutboxRepository outbox;
    private final TelemetryPointRepository telemetry;
    private final DeadLetterEventRepository deadLetters;

    public RetentionCleanupAttempt(ProcessedEventRepository processed,OutboxRepository outbox,TelemetryPointRepository telemetry,DeadLetterEventRepository deadLetters){this.processed=processed;this.outbox=outbox;this.telemetry=telemetry;this.deadLetters=deadLetters;}

    @Transactional
    public Result cleanup(Instant processedBefore,Instant outboxBefore,Instant telemetryBefore,Instant replayedDlqBefore,int batchSize){
        return new Result(processed.deleteBatchBefore(processedBefore,batchSize),outbox.deletePublishedBatchBefore(outboxBefore,batchSize),telemetry.deleteBatchBefore(telemetryBefore,batchSize),deadLetters.deleteTerminalBatchBefore(replayedDlqBefore,batchSize));
    }

    public record Result(int processedEvents,int outboxEvents,int telemetryPoints,int deadLetterEvents) {}
}
