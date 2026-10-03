package io.logitrack.alert;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

@Entity
@Table(name="alert_policy_audits")
public class AlertPolicyAudit {
    @Id private UUID id;
    @Column(name="policy_id",nullable=false) private UUID policyId;
    @Column(name="vehicle_id",nullable=false) private String vehicleId;
    @Column(name="deviation_open_meters",nullable=false) private double deviationOpenMeters;
    @Column(name="deviation_close_meters",nullable=false) private double deviationCloseMeters;
    @Column(name="critical_deviation_meters",nullable=false) private double criticalDeviationMeters;
    @Column(name="delay_open_seconds",nullable=false) private long delayOpenSeconds;
    @Column(name="delay_close_seconds",nullable=false) private long delayCloseSeconds;
    @Column(name="critical_delay_seconds",nullable=false) private long criticalDelaySeconds;
    @Enumerated(EnumType.STRING) @Column(nullable=false) private Action action;
    @Column(name="request_key",length=160) private String requestKey;
    @Column(name="policy_updated_at") private Instant policyUpdatedAt;
    @Column(name="restored_from_audit_id") private UUID restoredFromAuditId;
    @Column(nullable=false) private String actor;
    @Column(name="occurred_at",nullable=false) private Instant occurredAt;
    protected AlertPolicyAudit() {}
    public AlertPolicyAudit(AlertPolicy policy,String actor){this(policy,actor,Action.UPSERT);}
    public AlertPolicyAudit(AlertPolicy policy,String actor,Action action){this(policy,actor,action,null);}
    public AlertPolicyAudit(AlertPolicy policy,String actor,Action action,String requestKey){id=UUID.randomUUID();policyId=policy.getId();vehicleId=policy.getVehicleId();
        deviationOpenMeters=policy.getDeviationOpenMeters();deviationCloseMeters=policy.getDeviationCloseMeters();criticalDeviationMeters=policy.getCriticalDeviationMeters();
        delayOpenSeconds=policy.getDelayOpenSeconds();delayCloseSeconds=policy.getDelayCloseSeconds();criticalDelaySeconds=policy.getCriticalDelaySeconds();
        this.action=action;this.actor=actor;this.requestKey=requestKey;policyUpdatedAt=policy.getUpdatedAt();occurredAt=Instant.now();}
    public AlertPolicyAudit(AlertPolicy policy,String actor,String requestKey){this(policy,actor,Action.UPSERT);this.requestKey=Objects.requireNonNull(requestKey);}
    public AlertPolicyAudit(AlertPolicy policy,String actor,UUID restoredFromAuditId){this(policy,actor,restoredFromAuditId,null);}
    public AlertPolicyAudit(AlertPolicy policy,String actor,UUID restoredFromAuditId,String requestKey){this(policy,actor,Action.RESTORE,requestKey);this.restoredFromAuditId=Objects.requireNonNull(restoredFromAuditId);}
    public void bindRequestKey(String key){if(requestKey!=null)throw new IllegalStateException("Audit request key cannot be changed");requestKey=Objects.requireNonNull(key);}
    public UUID getId(){return id;} public UUID getPolicyId(){return policyId;} public String getVehicleId(){return vehicleId;}
    public double getDeviationOpenMeters(){return deviationOpenMeters;} public double getDeviationCloseMeters(){return deviationCloseMeters;}
    public double getCriticalDeviationMeters(){return criticalDeviationMeters;} public long getDelayOpenSeconds(){return delayOpenSeconds;}
    public long getDelayCloseSeconds(){return delayCloseSeconds;} public long getCriticalDelaySeconds(){return criticalDelaySeconds;}
    public Action getAction(){return action;} public String getActor(){return actor;} public String getRequestKey(){return requestKey;} public Instant getPolicyUpdatedAt(){return policyUpdatedAt;} public UUID getRestoredFromAuditId(){return restoredFromAuditId;} public Instant getOccurredAt(){return occurredAt;}
    public enum Action { UPSERT, RESET, RESTORE }
}
