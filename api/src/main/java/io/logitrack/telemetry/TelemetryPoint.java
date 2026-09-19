package io.logitrack.telemetry;

import io.logitrack.delivery.Delivery;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name="telemetry_points")
public class TelemetryPoint {
    @Id @Column(name="event_id") private UUID eventId;
    @Column(name="delivery_id",nullable=false) private UUID deliveryId;
    @Column(name="vehicle_id",nullable=false) private String vehicleId;
    @Column(nullable=false) private double latitude;
    @Column(nullable=false) private double longitude;
    @Column(nullable=false) private double progress;
    @Column(name="occurred_at",nullable=false) private Instant occurredAt;
    protected TelemetryPoint() {}
    public TelemetryPoint(UUID eventId,Delivery delivery,double latitude,double longitude,double progress,Instant occurredAt){
        this.eventId=eventId;this.deliveryId=delivery.getId();this.vehicleId=delivery.getVehicleId();this.latitude=latitude;this.longitude=longitude;this.progress=progress;this.occurredAt=occurredAt;
    }
    public UUID getEventId(){return eventId;} public UUID getDeliveryId(){return deliveryId;} public String getVehicleId(){return vehicleId;}
    public double getLatitude(){return latitude;} public double getLongitude(){return longitude;} public double getProgress(){return progress;} public Instant getOccurredAt(){return occurredAt;}
}
