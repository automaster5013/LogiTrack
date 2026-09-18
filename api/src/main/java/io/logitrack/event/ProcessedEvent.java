package io.logitrack.event;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name="processed_events")
public class ProcessedEvent {
    @Id @Column(name="event_id") private UUID eventId;
    @Column(name="consumer_name",nullable=false) private String consumerName;
    @Column(name="processed_at",nullable=false) private Instant processedAt;
    protected ProcessedEvent(){}
    public ProcessedEvent(UUID id,String consumer){eventId=id;consumerName=consumer;processedAt=Instant.now();}
}

