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

    protected OutboxEvent() {}
    public OutboxEvent(UUID id, String aggregateType, UUID aggregateId, String eventType, String topic, String eventKey, String payload) {
        this.id=id; this.aggregateType=aggregateType; this.aggregateId=aggregateId; this.eventType=eventType;
        this.topic=topic; this.eventKey=eventKey; this.payload=payload; this.status=Status.PENDING; this.createdAt=Instant.now();
    }
    public void published(){status=Status.PUBLISHED;publishedAt=Instant.now();lastError=null;}
    public void failed(Throwable error){attempts++;lastError=truncate(error.getMessage());if(attempts>=20)status=Status.FAILED;}
    private String truncate(String value){if(value==null)return errorName();return value.substring(0,Math.min(1000,value.length()));}
    private String errorName(){return "Unknown publishing error";}
    public UUID getId(){return id;} public String getTopic(){return topic;} public String getEventKey(){return eventKey;}
    public String getPayload(){return payload;} public Status getStatus(){return status;} public int getAttempts(){return attempts;}
    public enum Status { PENDING, PUBLISHED, FAILED }
}

