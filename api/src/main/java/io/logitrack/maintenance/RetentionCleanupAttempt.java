package io.logitrack.maintenance;

import io.logitrack.event.ProcessedEventRepository;
import io.logitrack.outbox.OutboxRepository;
import io.logitrack.telemetry.TelemetryPointRepository;
import io.logitrack.replay.DeadLetterEventRepository;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.jdbc.core.JdbcTemplate;
import java.time.Instant;
import java.util.Optional;

@Component
public class RetentionCleanupAttempt {
    private final ProcessedEventRepository processed;
    private final OutboxRepository outbox;
    private final TelemetryPointRepository telemetry;
    private final DeadLetterEventRepository deadLetters;
    private final JdbcTemplate jdbc;

    public RetentionCleanupAttempt(ProcessedEventRepository processed,OutboxRepository outbox,TelemetryPointRepository telemetry,DeadLetterEventRepository deadLetters,JdbcTemplate jdbc){this.processed=processed;this.outbox=outbox;this.telemetry=telemetry;this.deadLetters=deadLetters;this.jdbc=jdbc;}

    @Transactional
    public Optional<Result> cleanup(Instant processedBefore,Instant outboxBefore,Instant telemetryBefore,Instant replayedDlqBefore,int batchSize){
        var acquired=jdbc.queryForObject("SELECT pg_try_advisory_xact_lock(hashtextextended('retention-cleanup',0))",Boolean.class);
        if(!Boolean.TRUE.equals(acquired))return Optional.empty();
        return Optional.of(new Result(processed.deleteBatchBefore(processedBefore,batchSize),outbox.deletePublishedBatchBefore(outboxBefore,batchSize),telemetry.deleteBatchBefore(telemetryBefore,batchSize),deadLetters.deleteTerminalBatchBefore(replayedDlqBefore,batchSize)));
    }

    public record Result(int processedEvents,int outboxEvents,int telemetryPoints,int deadLetterEvents) {}
}
