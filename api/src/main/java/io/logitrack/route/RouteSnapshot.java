package io.logitrack.route;

import com.fasterxml.jackson.databind.JsonNode;
import io.logitrack.delivery.Delivery;
import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name="route_snapshots")
public class RouteSnapshot {
    @Id private UUID id;
    @Column(name="delivery_id",nullable=false) private UUID deliveryId;
    @Column(nullable=false) private String provider;
    @Column(name="algorithm_version",nullable=false) private String algorithmVersion;
    @JdbcTypeCode(SqlTypes.JSON) @Column(nullable=false,columnDefinition="jsonb") private JsonNode geometry;
    @Column(name="geometry_hash",nullable=false) private String geometryHash;
    @Column(name="distance_meters",nullable=false) private long distanceMeters;
    @Column(name="duration_seconds",nullable=false) private long durationSeconds;
    @Column(name="planned_eta",nullable=false) private Instant plannedEta;
    @Column(name="generated_at",nullable=false) private Instant generatedAt;
    protected RouteSnapshot() {}
    public RouteSnapshot(Delivery delivery,RoutePlan plan,JsonNode geometry){id=plan.routeId();deliveryId=delivery.getId();provider=plan.provider();algorithmVersion=plan.algorithmVersion();this.geometry=geometry;geometryHash=plan.geometryHash();distanceMeters=plan.distanceMeters();durationSeconds=plan.durationSeconds();plannedEta=plan.plannedEta();generatedAt=plan.generatedAt();}
    public UUID getId(){return id;} public UUID getDeliveryId(){return deliveryId;} public String getProvider(){return provider;}
    public String getAlgorithmVersion(){return algorithmVersion;} public JsonNode getGeometry(){return geometry;} public String getGeometryHash(){return geometryHash;}
    public long getDistanceMeters(){return distanceMeters;} public long getDurationSeconds(){return durationSeconds;} public Instant getPlannedEta(){return plannedEta;} public Instant getGeneratedAt(){return generatedAt;}
}

