package io.logitrack.replay;

import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Propagation;
import io.micrometer.core.instrument.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Service
public class ReplayService {
    private static final Logger log=LoggerFactory.getLogger(ReplayService.class);
    private final DeadLetterEventRepository events;
    private final ReplayAuditRepository audits;
    private final KafkaTemplate<Object, Object> kafka;
    private final Counter replayCounter;

    public ReplayService(DeadLetterEventRepository events, ReplayAuditRepository audits, KafkaTemplate<Object, Object> kafka,MeterRegistry metrics) {
        this.events=events; this.audits=audits; this.kafka=kafka;this.replayCounter=metrics.counter("logitrack.dlq.replays");
    }

    public List<DeadLetterEvent> list(DeadLetterEvent.Status status) {
        return status == null ? events.findTop100ByOrderByFailedAtDesc() : events.findTop100ByStatusOrderByFailedAtDesc(status);
    }
    public List<ReplayAudit> audits() { return audits.findTop100ByOrderByOccurredAtDesc(); }

    @Transactional(propagation=Propagation.REQUIRES_NEW)
    public DeadLetterEvent replay(UUID id, String actor) {
        var normalizedActor = actor == null ? "unknown" : actor.trim();
        if (normalizedActor.isBlank() || normalizedActor.length() > 120) throw new IllegalArgumentException("X-Operator must be 1-120 characters");
        var event = events.lockById(id).orElseThrow(() -> new java.util.NoSuchElementException("DLQ event not found"));
        if (event.getStatus() != DeadLetterEvent.Status.PENDING) throw new IllegalStateException("DLQ event has already been replayed");
        try {
            kafka.send(event.getOriginalTopic(), event.getMessageKey(), event.getPayload()).get(5, TimeUnit.SECONDS);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();log.warn("DLQ replay interrupted eventId={}",id,interrupted);
            throw new IllegalStateException("Could not publish replay event");
        } catch (Exception exception) {
            log.warn("DLQ replay publish failed eventId={}",id,exception);
            throw new IllegalStateException("Could not publish replay event");
        }
        event.markReplayed(normalizedActor);
        audits.save(new ReplayAudit(event.getId(), normalizedActor));
        replayCounter.increment();
        return event;
    }
}
