package io.logitrack.outbox;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "outbox_events")
public class OutboxEvent {
    @Id private UUID id;
    @Column(name="aggregate_type",nullable=false) private String aggregateType;
    @Column(name="aggregate_id",nullable=false) private UUID aggregateId;
    @Column(name="event_type",nullable=false) private String eventType;
    @Column(nullable=false) private String topic;
    @Column(name="event_key",nullable=false) private String eventKey;
    @Column(nullable=false,columnDefinition="TEXT") private String payload;
    @Enumerated(EnumType.STRING) @Column(nullable=false) private Status status;
    @Column(nullable=false) private int attempts;
    @Column(name="last_error") private String lastError;
    @Column(name="created_at",nullable=false) private Instant createdAt;
    @Column(name="published_at") private Instant publishedAt;
    @Column(name="next_attempt_at",nullable=false) private Instant nextAttemptAt;

    protected OutboxEvent() {}
    public OutboxEvent(UUID id, String aggregateType, UUID aggregateId, String eventType, String topic, String eventKey, String payload) {
        this.id=id; this.aggregateType=aggregateType; this.aggregateId=aggregateId; this.eventType=eventType;
        this.topic=topic; this.eventKey=eventKey; this.payload=payload; this.status=Status.PENDING; this.createdAt=Instant.now();this.nextAttemptAt=createdAt;
    }
    public void published(){status=Status.PUBLISHED;publishedAt=Instant.now();lastError=null;}
    public void failed(Throwable error){attempts++;lastError=truncate(error.getMessage());if(attempts>=20)status=Status.FAILED;else nextAttemptAt=Instant.now().plusSeconds(Math.min(300,1L<<Math.min(attempts-1,8)));}
    public void retry(){if(status!=Status.FAILED)throw new IllegalStateException("Only FAILED outbox events can be retried");status=Status.PENDING;attempts=0;lastError=null;publishedAt=null;nextAttemptAt=Instant.now();}
    private String truncate(String value){if(value==null)return errorName();return value.substring(0,Math.min(1000,value.length()));}
    private String errorName(){return "Unknown publishing error";}
    public UUID getId(){return id;} public String getAggregateType(){return aggregateType;} public UUID getAggregateId(){return aggregateId;}
    public String getEventType(){return eventType;} public String getTopic(){return topic;} public String getEventKey(){return eventKey;}
    public String getPayload(){return payload;} public Status getStatus(){return status;} public int getAttempts(){return attempts;}
    public String getLastError(){return lastError;} public Instant getCreatedAt(){return createdAt;} public Instant getPublishedAt(){return publishedAt;}public Instant getNextAttemptAt(){return nextAttemptAt;}
    public enum Status { PENDING, PUBLISHED, FAILED }
}
