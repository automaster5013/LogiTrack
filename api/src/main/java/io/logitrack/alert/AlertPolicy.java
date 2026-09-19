package io.logitrack.alert;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name="alert_policies")
public class AlertPolicy {
    public static final String DEFAULT_VEHICLE="*";
    @Id private UUID id;
    @Column(name="vehicle_id",nullable=false,unique=true) private String vehicleId;
    @Column(name="deviation_open_meters",nullable=false) private double deviationOpenMeters;
    @Column(name="deviation_close_meters",nullable=false) private double deviationCloseMeters;
    @Column(name="critical_deviation_meters",nullable=false) private double criticalDeviationMeters;
    @Column(name="delay_open_seconds",nullable=false) private long delayOpenSeconds;
    @Column(name="delay_close_seconds",nullable=false) private long delayCloseSeconds;
    @Column(name="critical_delay_seconds",nullable=false) private long criticalDelaySeconds;
    @Column(name="updated_at",nullable=false) private Instant updatedAt;
    @Column(name="updated_by",nullable=false) private String updatedBy;
    @Column(nullable=false) private boolean active;
    @Version private long version;

    protected AlertPolicy() {}
    public AlertPolicy(String vehicleId,double deviationOpenMeters,double deviationCloseMeters,double criticalDeviationMeters,
        long delayOpenSeconds,long delayCloseSeconds,long criticalDelaySeconds,String actor){
        id=UUID.randomUUID();this.vehicleId=vehicleId;update(deviationOpenMeters,deviationCloseMeters,criticalDeviationMeters,
            delayOpenSeconds,delayCloseSeconds,criticalDelaySeconds,actor);
    }
    public void update(double deviationOpenMeters,double deviationCloseMeters,double criticalDeviationMeters,
        long delayOpenSeconds,long delayCloseSeconds,long criticalDelaySeconds,String actor){
        validate(deviationOpenMeters,deviationCloseMeters,criticalDeviationMeters,delayOpenSeconds,delayCloseSeconds,criticalDelaySeconds);
        this.deviationOpenMeters=deviationOpenMeters;this.deviationCloseMeters=deviationCloseMeters;this.criticalDeviationMeters=criticalDeviationMeters;
        this.delayOpenSeconds=delayOpenSeconds;this.delayCloseSeconds=delayCloseSeconds;this.criticalDelaySeconds=criticalDelaySeconds;
        updatedAt=Instant.now();updatedBy=actor;active=true;
    }
    public void deactivate(String actor){if(DEFAULT_VEHICLE.equals(vehicleId))throw new IllegalArgumentException("Global default policy cannot be reset");
        active=false;updatedAt=Instant.now();updatedBy=actor;}
    static void validate(double deviationOpenMeters,double deviationCloseMeters,double criticalDeviationMeters,
        long delayOpenSeconds,long delayCloseSeconds,long criticalDelaySeconds){
        if(!Double.isFinite(deviationOpenMeters)||!Double.isFinite(deviationCloseMeters)||!Double.isFinite(criticalDeviationMeters)
            ||deviationCloseMeters<0||deviationCloseMeters>=deviationOpenMeters||deviationOpenMeters>criticalDeviationMeters)
            throw new IllegalArgumentException("Deviation thresholds must satisfy 0 <= close < open <= critical");
        if(delayCloseSeconds<0||delayCloseSeconds>=delayOpenSeconds||delayOpenSeconds>criticalDelaySeconds)
            throw new IllegalArgumentException("Delay thresholds must satisfy 0 <= close < open <= critical");
    }
    public UUID getId(){return id;} public String getVehicleId(){return vehicleId;}
    public double getDeviationOpenMeters(){return deviationOpenMeters;} public double getDeviationCloseMeters(){return deviationCloseMeters;}
    public double getCriticalDeviationMeters(){return criticalDeviationMeters;} public long getDelayOpenSeconds(){return delayOpenSeconds;}
    public long getDelayCloseSeconds(){return delayCloseSeconds;} public long getCriticalDelaySeconds(){return criticalDelaySeconds;}
    public Instant getUpdatedAt(){return updatedAt;} public String getUpdatedBy(){return updatedBy;} public boolean isActive(){return active;}
}
