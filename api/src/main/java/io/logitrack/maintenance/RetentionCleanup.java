package io.logitrack.maintenance;

import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.atomic.AtomicBoolean;

@Component
public class RetentionCleanup {
    private static final Logger log=LoggerFactory.getLogger(RetentionCleanup.class);
    private static final Duration MIN_RETENTION=Duration.ofDays(1);
    private final RetentionCleanupAttempt attempt;
    private final MeterRegistry metrics;
    private final Duration processedRetention;
    private final Duration outboxRetention;
    private final Duration telemetryRetention;
    private final Duration replayedDlqRetention;
    private final int batchSize;
    private final AtomicBoolean cleanupHealthy=new AtomicBoolean(true);

    public RetentionCleanup(RetentionCleanupAttempt attempt,MeterRegistry metrics,
        @Value("${logitrack.retention.processed-events:30d}") Duration processedRetention,
        @Value("${logitrack.retention.published-outbox:7d}") Duration outboxRetention,
        @Value("${logitrack.retention.telemetry:30d}") Duration telemetryRetention,
        @Value("${logitrack.retention.replayed-dlq:90d}") Duration replayedDlqRetention,
        @Value("${logitrack.retention.batch-size:1000}") int batchSize){
        validate(processedRetention,"Processed-event");validate(outboxRetention,"Published-outbox");validate(telemetryRetention,"Telemetry");validate(replayedDlqRetention,"Replayed-DLQ");
        if(batchSize<1||batchSize>10_000)throw new IllegalArgumentException("Retention batch size must be between 1 and 10000");
        this.attempt=attempt;this.metrics=metrics;this.processedRetention=processedRetention;this.outboxRetention=outboxRetention;this.telemetryRetention=telemetryRetention;this.replayedDlqRetention=replayedDlqRetention;this.batchSize=batchSize;
        for(var table:new String[]{"processed_events","outbox_events","telemetry_points","dead_letter_events"})metrics.counter("logitrack.retention.deleted","table",table);
        metrics.counter("logitrack.retention.failures");
    }

    @Scheduled(initialDelayString="${logitrack.retention.initial-delay-ms:60000}",fixedDelayString="${logitrack.retention.poll-delay-ms:300000}")
    public void cleanup(){
        var now=Instant.now();
        try {
            var result=attempt.cleanup(now.minus(processedRetention),now.minus(outboxRetention),now.minus(telemetryRetention),now.minus(replayedDlqRetention),batchSize);
            record("processed_events",result.processedEvents());
            record("outbox_events",result.outboxEvents());
            record("telemetry_points",result.telemetryPoints());
            record("dead_letter_events",result.deadLetterEvents());
            if(!cleanupHealthy.getAndSet(true))log.info("Retention cleanup recovered");
        } catch(RuntimeException error){
            metrics.counter("logitrack.retention.failures").increment();
            if(cleanupHealthy.getAndSet(false))log.warn("Retention cleanup failed; scheduled retries will continue: {}",error.toString());
        }
    }
    private void record(String table,int count){metrics.counter("logitrack.retention.deleted","table",table).increment(count);}
    private static void validate(Duration value,String name){if(value.compareTo(MIN_RETENTION)<0)throw new IllegalArgumentException(name+" retention must be at least one day");}
}
