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
    @Column(name="request_key",length=160,unique=true) private String requestKey;
    @Column(name="occurred_at", nullable=false) private Instant occurredAt;
    protected ReplayAudit() {}
    public ReplayAudit(UUID eventId, String actor) { this(eventId,"REPLAY",actor,null,null); }
    public ReplayAudit(UUID eventId, String action, String actor, String reason) { this(eventId,action,actor,reason,null); }
    public ReplayAudit(UUID eventId, String action, String actor, String reason,String requestKey) { id=UUID.randomUUID();deadLetterEventId=eventId;this.action=action;this.actor=actor;this.reason=reason;this.requestKey=requestKey;occurredAt=Instant.now(); }
    public UUID getId(){return id;} public UUID getDeadLetterEventId(){return deadLetterEventId;} public String getAction(){return action;} public String getActor(){return actor;} public String getReason(){return reason;} public String getRequestKey(){return requestKey;} public Instant getOccurredAt(){return occurredAt;}
}
