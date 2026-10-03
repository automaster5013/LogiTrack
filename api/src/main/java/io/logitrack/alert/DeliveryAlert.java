package io.logitrack.alert;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name="delivery_alerts")
public class DeliveryAlert {
    @Id private UUID id;
    @Column(name="delivery_id",nullable=false) private UUID deliveryId;
    @Enumerated(EnumType.STRING) @Column(name="alert_type",nullable=false) private Type alertType;
    @Enumerated(EnumType.STRING) @Column(nullable=false) private Severity severity;
    @Enumerated(EnumType.STRING) @Column(nullable=false) private Status status;
    @Column(nullable=false) private String message;
    @Column(name="observed_value",nullable=false) private double observedValue;
    @Column(name="threshold_value",nullable=false) private double thresholdValue;
    @Column(name="occurrence_count",nullable=false) private int occurrenceCount;
    @Column(name="first_observed_at",nullable=false) private Instant firstObservedAt;
    @Column(name="last_observed_at",nullable=false) private Instant lastObservedAt;
    @Column(name="resolved_at") private Instant resolvedAt;
    @Column(name="acknowledged_at") private Instant acknowledgedAt;
    @Column(name="acknowledged_by",length=120) private String acknowledgedBy;
    @Column(name="acknowledgement_request_key",length=160,unique=true) private String acknowledgementRequestKey;

    protected DeliveryAlert() {}
    public DeliveryAlert(UUID deliveryId,Type type,Severity severity,String message,double observedValue,double thresholdValue){
        var now=Instant.now();id=UUID.randomUUID();this.deliveryId=deliveryId;alertType=type;this.severity=severity;status=Status.ACTIVE;
        this.message=message;this.observedValue=observedValue;this.thresholdValue=thresholdValue;occurrenceCount=1;firstObservedAt=now;lastObservedAt=now;
    }
    public boolean observe(Severity nextSeverity,String nextMessage,double value){
        var escalated=nextSeverity.ordinal()>severity.ordinal();if(escalated)severity=nextSeverity;message=nextMessage;observedValue=value;occurrenceCount++;lastObservedAt=Instant.now();return escalated;
    }
    public void resolve(double value){status=Status.RESOLVED;observedValue=value;lastObservedAt=Instant.now();resolvedAt=lastObservedAt;}
    public boolean acknowledge(String actor){
        return acknowledge(actor,null);
    }
    public boolean acknowledge(String actor,String requestKey){
        if(status!=Status.ACTIVE)throw new IllegalStateException("Only active alerts can be acknowledged");
        if(acknowledgedAt!=null)return false;
        var normalized=actor==null?"":actor.trim();
        if(normalized.isBlank()||normalized.length()>120)throw new IllegalArgumentException("X-Operator must be 1-120 characters");
        acknowledgedBy=normalized;acknowledgementRequestKey=requestKey;acknowledgedAt=Instant.now();return true;
    }
    public void bindAcknowledgementRequestKey(String actor,String requestKey){
        var normalized=actor==null?"":actor.trim();
        if(acknowledgedAt==null)throw new IllegalStateException("Unacknowledged alert cannot claim a request key");
        if(acknowledgementRequestKey!=null)throw new IllegalStateException("Acknowledgement request key cannot be changed");
        if(!normalized.equals(acknowledgedBy))throw new IllegalStateException("Delivery alert was acknowledged by a different operator");
        acknowledgementRequestKey=requestKey;
    }
    public UUID getId(){return id;} public UUID getDeliveryId(){return deliveryId;} public Type getAlertType(){return alertType;}
    public Severity getSeverity(){return severity;} public Status getStatus(){return status;} public String getMessage(){return message;}
    public double getObservedValue(){return observedValue;} public double getThresholdValue(){return thresholdValue;} public int getOccurrenceCount(){return occurrenceCount;}
    public Instant getFirstObservedAt(){return firstObservedAt;} public Instant getLastObservedAt(){return lastObservedAt;} public Instant getResolvedAt(){return resolvedAt;}
    public Instant getAcknowledgedAt(){return acknowledgedAt;} public String getAcknowledgedBy(){return acknowledgedBy;} @com.fasterxml.jackson.annotation.JsonIgnore public String getAcknowledgementRequestKey(){return acknowledgementRequestKey;}
    public enum Type { DELAY, ROUTE_DEVIATION }
    public enum Severity { WARNING, CRITICAL }
    public enum Status { ACTIVE, RESOLVED }
}
