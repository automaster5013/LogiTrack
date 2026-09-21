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
import org.springframework.data.domain.*;

@Service
public class ReplayService {
    private static final Logger log=LoggerFactory.getLogger(ReplayService.class);
    private final DeadLetterEventRepository events;
    private final ReplayAuditRepository audits;
    private final KafkaTemplate<Object, Object> kafka;
    private final Counter replayCounter;
    private final Counter discardCounter;

    public ReplayService(DeadLetterEventRepository events, ReplayAuditRepository audits, KafkaTemplate<Object, Object> kafka,MeterRegistry metrics) {
        this.events=events; this.audits=audits; this.kafka=kafka;this.replayCounter=metrics.counter("logitrack.dlq.replays");this.discardCounter=metrics.counter("logitrack.dlq.discards");
    }

    public List<DeadLetterEvent> list(DeadLetterEvent.Status status) {
        return status == null ? events.findTop100ByOrderByFailedAtDesc() : events.findTop100ByStatusOrderByFailedAtDesc(status);
    }
    @Transactional(readOnly=true)
    public DeadLetterPage page(DeadLetterEvent.Status status,int page,int size){
        var pageable=PageRequest.of(page,size,Sort.by(Sort.Direction.DESC,"failedAt").and(Sort.by(Sort.Direction.DESC,"id")));
        Page<DeadLetterEvent> result=status==null?events.findAll(pageable):events.findByStatus(status,pageable);
        return new DeadLetterPage(result.getContent(),result.getNumber(),result.getSize(),result.getTotalElements(),result.hasNext());
    }
    public List<ReplayAudit> audits() { return audits.findTop100ByOrderByOccurredAtDesc(); }
    @Transactional(readOnly=true) public AuditPage auditPage(int page,int size){var result=audits.findAll(PageRequest.of(page,size,Sort.by(Sort.Direction.DESC,"occurredAt").and(Sort.by(Sort.Direction.DESC,"id"))));return new AuditPage(result.getContent(),result.getNumber(),result.getSize(),result.getTotalElements(),result.hasNext());}
    public record DeadLetterPage(List<DeadLetterEvent> items,int page,int size,long totalElements,boolean hasMore){}
    public record AuditPage(List<ReplayAudit> items,int page,int size,long totalElements,boolean hasMore){}

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

    @Transactional(propagation=Propagation.REQUIRES_NEW)
    public DeadLetterEvent discard(UUID id, String actor, String reason) {
        var normalizedActor = actor == null ? "" : actor.trim();
        var normalizedReason = reason == null ? "" : reason.trim();
        if (normalizedActor.isBlank() || normalizedActor.length() > 120) throw new IllegalArgumentException("X-Operator must be 1-120 characters");
        if (normalizedReason.isBlank() || normalizedReason.length() > 500) throw new IllegalArgumentException("reason must be 1-500 characters");
        var event = events.lockById(id).orElseThrow(() -> new java.util.NoSuchElementException("DLQ event not found"));
        event.discard(normalizedActor, normalizedReason);
        audits.save(new ReplayAudit(event.getId(), "DISCARD", normalizedActor, normalizedReason));
        discardCounter.increment();
        return event;
    }
}
