package io.logitrack.outbox;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name="outbox_retry_audits")
public class OutboxRetryAudit {
    @Id private UUID id;
    @Column(name="outbox_event_id",nullable=false) private UUID outboxEventId;
    @Column(nullable=false) private String actor;
    @Column(name="occurred_at",nullable=false) private Instant occurredAt;
    protected OutboxRetryAudit() {}
    public OutboxRetryAudit(UUID outboxEventId,String actor){id=UUID.randomUUID();this.outboxEventId=outboxEventId;this.actor=actor;occurredAt=Instant.now();}
    public UUID getId(){return id;} public UUID getOutboxEventId(){return outboxEventId;} public String getActor(){return actor;} public Instant getOccurredAt(){return occurredAt;}
}
