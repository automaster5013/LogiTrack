package io.logitrack.replay;

import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Service
public class ReplayService {
    private final DeadLetterEventRepository events;
    private final ReplayAuditRepository audits;
    private final KafkaTemplate<Object, Object> kafka;

    public ReplayService(DeadLetterEventRepository events, ReplayAuditRepository audits, KafkaTemplate<Object, Object> kafka) {
        this.events=events; this.audits=audits; this.kafka=kafka;
    }

    public List<DeadLetterEvent> list(DeadLetterEvent.Status status) {
        return status == null ? events.findTop100ByOrderByFailedAtDesc() : events.findTop100ByStatusOrderByFailedAtDesc(status);
    }
    public List<ReplayAudit> audits() { return audits.findTop100ByOrderByOccurredAtDesc(); }

    @Transactional
    public DeadLetterEvent replay(UUID id, String actor) {
        var normalizedActor = actor == null ? "unknown" : actor.trim();
        if (normalizedActor.isBlank() || normalizedActor.length() > 120) throw new IllegalArgumentException("X-Operator must be 1-120 characters");
        var event = events.findById(id).orElseThrow(() -> new java.util.NoSuchElementException("DLQ event not found"));
        if (event.getStatus() != DeadLetterEvent.Status.PENDING) throw new IllegalStateException("DLQ event has already been replayed");
        try {
            kafka.send(event.getOriginalTopic(), event.getMessageKey(), event.getPayload()).get(5, TimeUnit.SECONDS);
        } catch (Exception exception) {
            throw new IllegalStateException("Could not publish replay event: " + exception.getMessage());
        }
        event.markReplayed(normalizedActor);
        audits.save(new ReplayAudit(event.getId(), normalizedActor));
        return event;
    }
}

