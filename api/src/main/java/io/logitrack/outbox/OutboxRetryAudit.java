package io.logitrack.outbox;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name="outbox_retry_audits")
public class OutboxRetryAudit {
    @Id private UUID id;
    @Column(name="outbox_event_id",nullable=false) private UUID outboxEventId;
    @Column(nullable=false) private String actor;
    @Column(name="request_key",nullable=false,length=160,unique=true) private String requestKey;
    @Column(name="occurred_at",nullable=false) private Instant occurredAt;
    protected OutboxRetryAudit() {}
    public OutboxRetryAudit(UUID outboxEventId,String actor,String requestKey){id=UUID.randomUUID();this.outboxEventId=outboxEventId;this.actor=actor;this.requestKey=requestKey;occurredAt=Instant.now();}
    public UUID getId(){return id;} public UUID getOutboxEventId(){return outboxEventId;} public String getActor(){return actor;} public String getRequestKey(){return requestKey;} public Instant getOccurredAt(){return occurredAt;}
}
