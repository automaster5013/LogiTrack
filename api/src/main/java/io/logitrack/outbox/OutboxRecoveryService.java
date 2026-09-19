package io.logitrack.outbox;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import io.micrometer.core.instrument.*;
import java.util.*;

@Service
public class OutboxRecoveryService {
    private final OutboxRepository events; private final OutboxRetryAuditRepository audits; private final Counter retryCounter;
    public OutboxRecoveryService(OutboxRepository events,OutboxRetryAuditRepository audits,MeterRegistry metrics){this.events=events;this.audits=audits;this.retryCounter=metrics.counter("logitrack.outbox.retries");}
    public List<FailureView> failures(){return events.findTop50ByStatusOrderByCreatedAtDesc(OutboxEvent.Status.FAILED).stream().map(FailureView::from).toList();}
    public List<OutboxRetryAudit> audits(){return audits.findTop50ByOrderByOccurredAtDesc();}
    @Transactional public FailureView retry(UUID id,String actor){
        var normalized=normalize(actor);var event=events.lockById(id).orElseThrow();event.retry();audits.save(new OutboxRetryAudit(id,normalized));retryCounter.increment();return FailureView.from(event);
    }
    private String normalize(String actor){var value=actor==null?"":actor.trim();if(value.isEmpty()||value.length()>120)throw new IllegalArgumentException("X-Operator must be 1-120 characters");return value;}
    public record FailureView(UUID id,String aggregateType,UUID aggregateId,String eventType,String topic,int attempts,String lastError,java.time.Instant createdAt,OutboxEvent.Status status){
        static FailureView from(OutboxEvent event){return new FailureView(event.getId(),event.getAggregateType(),event.getAggregateId(),event.getEventType(),event.getTopic(),event.getAttempts(),event.getLastError(),event.getCreatedAt(),event.getStatus());}
    }
}
