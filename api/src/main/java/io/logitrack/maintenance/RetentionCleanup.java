package io.logitrack.maintenance;

import io.logitrack.event.ProcessedEventRepository;
import io.logitrack.outbox.OutboxRepository;
import io.logitrack.telemetry.TelemetryPointRepository;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import java.time.Duration;
import java.time.Instant;

@Component
public class RetentionCleanup {
    private static final Duration MIN_RETENTION=Duration.ofDays(1);
    private final ProcessedEventRepository processed;
    private final OutboxRepository outbox;
    private final TelemetryPointRepository telemetry;
    private final MeterRegistry metrics;
    private final Duration processedRetention;
    private final Duration outboxRetention;
    private final Duration telemetryRetention;
    private final int batchSize;

    public RetentionCleanup(ProcessedEventRepository processed,OutboxRepository outbox,TelemetryPointRepository telemetry,MeterRegistry metrics,
        @Value("${logitrack.retention.processed-events:30d}") Duration processedRetention,
        @Value("${logitrack.retention.published-outbox:7d}") Duration outboxRetention,
        @Value("${logitrack.retention.telemetry:30d}") Duration telemetryRetention,
        @Value("${logitrack.retention.batch-size:1000}") int batchSize){
        validate(processedRetention,"Processed-event");validate(outboxRetention,"Published-outbox");validate(telemetryRetention,"Telemetry");
        if(batchSize<1||batchSize>10_000)throw new IllegalArgumentException("Retention batch size must be between 1 and 10000");
        this.processed=processed;this.outbox=outbox;this.telemetry=telemetry;this.metrics=metrics;this.processedRetention=processedRetention;this.outboxRetention=outboxRetention;this.telemetryRetention=telemetryRetention;this.batchSize=batchSize;
        for(var table:new String[]{"processed_events","outbox_events","telemetry_points"})metrics.counter("logitrack.retention.deleted","table",table);
    }

    @Scheduled(initialDelayString="${logitrack.retention.initial-delay-ms:60000}",fixedDelayString="${logitrack.retention.poll-delay-ms:300000}")
    @Transactional
    public void cleanup(){
        var now=Instant.now();
        record("processed_events",processed.deleteBatchBefore(now.minus(processedRetention),batchSize));
        record("outbox_events",outbox.deletePublishedBatchBefore(now.minus(outboxRetention),batchSize));
        record("telemetry_points",telemetry.deleteBatchBefore(now.minus(telemetryRetention),batchSize));
    }
    private void record(String table,int count){metrics.counter("logitrack.retention.deleted","table",table).increment(count);}
    private static void validate(Duration value,String name){if(value.compareTo(MIN_RETENTION)<0)throw new IllegalArgumentException(name+" retention must be at least one day");}
}
