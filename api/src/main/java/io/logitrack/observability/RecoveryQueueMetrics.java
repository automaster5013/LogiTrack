package io.logitrack.observability;

import io.logitrack.outbox.OutboxEvent;
import io.logitrack.outbox.OutboxRepository;
import io.logitrack.replay.DeadLetterEvent;
import io.logitrack.replay.DeadLetterEventRepository;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicLong;

@Component
public class RecoveryQueueMetrics {
    private static final Logger log=LoggerFactory.getLogger(RecoveryQueueMetrics.class);
    private final OutboxRepository outbox;
    private final DeadLetterEventRepository deadLetters;
    private final AtomicLong pendingOutbox=new AtomicLong();
    private final AtomicLong failedOutbox=new AtomicLong();
    private final AtomicLong pendingDeadLetters=new AtomicLong();

    public RecoveryQueueMetrics(OutboxRepository outbox,DeadLetterEventRepository deadLetters,MeterRegistry registry){
        this.outbox=outbox;this.deadLetters=deadLetters;
        registry.gauge("logitrack.outbox.backlog",java.util.List.of(io.micrometer.core.instrument.Tag.of("status","pending")),pendingOutbox,AtomicLong::get);
        registry.gauge("logitrack.outbox.backlog",java.util.List.of(io.micrometer.core.instrument.Tag.of("status","failed")),failedOutbox,AtomicLong::get);
        registry.gauge("logitrack.dlq.backlog",pendingDeadLetters);
    }

    @Scheduled(fixedDelayString="${logitrack.metrics.recovery-refresh-ms:10000}")
    public void refresh(){
        try{
            pendingOutbox.set(outbox.countByStatus(OutboxEvent.Status.PENDING));
            failedOutbox.set(outbox.countByStatus(OutboxEvent.Status.FAILED));
            pendingDeadLetters.set(deadLetters.countByStatus(DeadLetterEvent.Status.PENDING));
        }catch(Exception error){log.warn("Could not refresh recovery queue metrics",error);}
    }
}
