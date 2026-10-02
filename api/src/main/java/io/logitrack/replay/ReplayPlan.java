package io.logitrack.replay;

import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name="replay_plans")
public class ReplayPlan {
    @Id private UUID id;
    @Column(nullable=false) private String actor;
    @Column(name="request_key",nullable=false,length=160,unique=true) private String requestKey;
    @JdbcTypeCode(SqlTypes.JSON) @Column(name="event_ids", nullable=false, columnDefinition="jsonb") private List<UUID> eventIds;
    @Enumerated(EnumType.STRING) @Column(nullable=false) private Status status;
    @Column(name="created_at",nullable=false) private Instant createdAt;
    @Column(name="expires_at",nullable=false) private Instant expiresAt;
    @Column(name="executed_at") private Instant executedAt;
    @Column(name="execution_request_key",length=160,unique=true) private String executionRequestKey;
    @Column(name="succeeded_count",nullable=false) private int succeededCount;
    @Column(name="failed_count",nullable=false) private int failedCount;

    protected ReplayPlan() {}
    ReplayPlan(String actor,List<UUID> eventIds){this(actor,UUID.randomUUID().toString(),eventIds);}
    public ReplayPlan(String actor,String requestKey,List<UUID> eventIds) {
        id=UUID.randomUUID();this.actor=actor;this.requestKey=requestKey;this.eventIds=List.copyOf(eventIds);status=Status.PREPARED;
        createdAt=Instant.now();expiresAt=createdAt.plus(10, ChronoUnit.MINUTES);
    }
    public void expire() { if(status==Status.PREPARED) status=Status.EXPIRED; }
    public void bindExecutionRequest(String requestKey){executionRequestKey=requestKey;}
    public void complete(int succeeded, int failed) {
        if(status!=Status.PREPARED) throw new IllegalStateException("Replay plan is not executable");
        succeededCount=succeeded;failedCount=failed;executedAt=Instant.now();status=failed==0?Status.EXECUTED:Status.PARTIAL;
    }
    public UUID getId(){return id;} public String getActor(){return actor;} public String getRequestKey(){return requestKey;} public List<UUID> getEventIds(){return eventIds;}
    public Status getStatus(){return status;} public Instant getCreatedAt(){return createdAt;} public Instant getExpiresAt(){return expiresAt;}
    public Instant getExecutedAt(){return executedAt;} public int getSucceededCount(){return succeededCount;} public int getFailedCount(){return failedCount;}
    @com.fasterxml.jackson.annotation.JsonIgnore public String getExecutionRequestKey(){return executionRequestKey;}
    public enum Status { PREPARED, EXECUTED, PARTIAL, EXPIRED }
}

