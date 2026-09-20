package io.logitrack.replay;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name="replay_audits")
public class ReplayAudit {
    @Id private UUID id;
    @Column(name="dead_letter_event_id", nullable=false) private UUID deadLetterEventId;
    @Column(nullable=false) private String action;
    @Column(nullable=false) private String actor;
    @Column private String reason;
    @Column(name="occurred_at", nullable=false) private Instant occurredAt;
    protected ReplayAudit() {}
    public ReplayAudit(UUID eventId, String actor) { this(eventId,"REPLAY",actor,null); }
    public ReplayAudit(UUID eventId, String action, String actor, String reason) { id=UUID.randomUUID();deadLetterEventId=eventId;this.action=action;this.actor=actor;this.reason=reason;occurredAt=Instant.now(); }
    public UUID getId(){return id;} public UUID getDeadLetterEventId(){return deadLetterEventId;} public String getAction(){return action;} public String getActor(){return actor;} public String getReason(){return reason;} public Instant getOccurredAt(){return occurredAt;}
}
