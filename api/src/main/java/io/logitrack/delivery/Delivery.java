package io.logitrack.delivery;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "deliveries")
public class Delivery {
    @Id private UUID id;
    @Column(name="order_number", nullable=false) private String orderNumber;
    @Column(name="order_id") private UUID orderId;
    @Column(name="vehicle_id", nullable=false) private String vehicleId;
    @Enumerated(EnumType.STRING) @Column(nullable=false) private Status status;
    @Column(name="origin_name", nullable=false) private String originName;
    @Column(name="origin_lat", nullable=false) private double originLat;
    @Column(name="origin_lon", nullable=false) private double originLon;
    @Column(name="destination_name", nullable=false) private String destinationName;
    @Column(name="destination_lat", nullable=false) private double destinationLat;
    @Column(name="destination_lon", nullable=false) private double destinationLon;
    @Column(name="current_lat") private Double currentLat;
    @Column(name="current_lon") private Double currentLon;
    @Column(nullable=false) private double progress;
    private Instant eta;
    @Column(name="idempotency_key", nullable=false, unique=true) private String idempotencyKey;
    @Version private long version;
    @Column(name="created_at", nullable=false) private Instant createdAt;
    @Column(name="updated_at", nullable=false) private Instant updatedAt;

    protected Delivery() {}
    public static Delivery create(CreateDeliveryRequest r, String key) {
        return create(r, key, null);
    }
    public static Delivery create(CreateDeliveryRequest r, String key, UUID orderId) {
        var d = new Delivery(); var now = Instant.now();
        d.id=UUID.randomUUID(); d.orderId=orderId; d.orderNumber=r.orderNumber(); d.vehicleId=r.vehicleId(); d.status=Status.CREATED;
        d.originName=r.origin().name(); d.originLat=r.origin().lat(); d.originLon=r.origin().lon();
        d.destinationName=r.destination().name(); d.destinationLat=r.destination().lat(); d.destinationLon=r.destination().lon();
        d.currentLat=d.originLat; d.currentLon=d.originLon; d.progress=0; d.idempotencyKey=key; d.createdAt=now; d.updatedAt=now;
        return d;
    }
    public void applyTelemetry(double lat, double lon, double progress, Instant eta, Status status) {
        if(!Double.isFinite(lat)||!Double.isFinite(lon)||!Double.isFinite(progress)||lat < -90||lat > 90||lon < -180||lon > 180||progress < 0||progress > 1)
            throw new IllegalArgumentException("Invalid telemetry coordinates or progress");
        if(status==null)throw new IllegalArgumentException("Telemetry status is required");
        if (this.status == Status.DELIVERED) return;
        this.currentLat=lat; this.currentLon=lon; this.progress=progress; this.eta=eta; this.status=status; this.updatedAt=Instant.now();
    }
    public UUID getId(){return id;} public UUID getOrderId(){return orderId;} public String getOrderNumber(){return orderNumber;} public String getVehicleId(){return vehicleId;}
    public Status getStatus(){return status;} public String getOriginName(){return originName;} public double getOriginLat(){return originLat;}
    public double getOriginLon(){return originLon;} public String getDestinationName(){return destinationName;} public double getDestinationLat(){return destinationLat;}
    public double getDestinationLon(){return destinationLon;} public Double getCurrentLat(){return currentLat;} public Double getCurrentLon(){return currentLon;}
    public double getProgress(){return progress;} public Instant getEta(){return eta;} public Instant getCreatedAt(){return createdAt;} public Instant getUpdatedAt(){return updatedAt;}
    public enum Status { CREATED, IN_TRANSIT, DELAYED, DELIVERED }
}
