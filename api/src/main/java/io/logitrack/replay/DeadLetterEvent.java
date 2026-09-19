package io.logitrack.replay;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "dead_letter_events", uniqueConstraints = @UniqueConstraint(columnNames = {"dlq_topic", "dlq_partition", "dlq_offset"}))
public class DeadLetterEvent {
    @Id private UUID id;
    @Column(name="original_topic", nullable=false) private String originalTopic;
    @Column(name="message_key") private String messageKey;
    @Column(nullable=false, columnDefinition="text") private String payload;
    @Column(name="trace_id") private String traceId;
    @Column(name="exception_message") private String exceptionMessage;
    @Column(name="dlq_topic", nullable=false) private String dlqTopic;
    @Column(name="dlq_partition", nullable=false) private int dlqPartition;
    @Column(name="dlq_offset", nullable=false) private long dlqOffset;
    @Enumerated(EnumType.STRING) @Column(nullable=false) private Status status;
    @Column(name="failed_at", nullable=false) private Instant failedAt;
    @Column(name="replayed_at") private Instant replayedAt;
    @Column(name="replayed_by") private String replayedBy;

    protected DeadLetterEvent() {}

    public DeadLetterEvent(String originalTopic, String messageKey, String payload, String traceId,
                           String exceptionMessage, String dlqTopic, int dlqPartition, long dlqOffset) {
        this.id = UUID.randomUUID(); this.originalTopic = originalTopic; this.messageKey = messageKey;
        this.payload = payload; this.traceId = traceId; this.exceptionMessage = exceptionMessage;
        this.dlqTopic = dlqTopic; this.dlqPartition = dlqPartition; this.dlqOffset = dlqOffset;
        this.status = Status.PENDING; this.failedAt = Instant.now();
    }

    public void markReplayed(String actor) {
        if (status != Status.PENDING) throw new IllegalStateException("DLQ event has already been replayed");
        status = Status.REPLAYED; replayedAt = Instant.now(); replayedBy = actor;
    }

    public UUID getId(){return id;} public String getOriginalTopic(){return originalTopic;} public String getMessageKey(){return messageKey;}
    public String getPayload(){return payload;} public String getTraceId(){return traceId;} public String getExceptionMessage(){return exceptionMessage;}
    public String getDlqTopic(){return dlqTopic;} public int getDlqPartition(){return dlqPartition;} public long getDlqOffset(){return dlqOffset;}
    public Status getStatus(){return status;} public Instant getFailedAt(){return failedAt;} public Instant getReplayedAt(){return replayedAt;} public String getReplayedBy(){return replayedBy;}
    public enum Status { PENDING, REPLAYED }
}

