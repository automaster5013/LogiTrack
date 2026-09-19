package io.logitrack.order;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "orders")
public class CustomerOrder {
    @Id private UUID id;
    @Column(name="order_number", nullable=false, unique=true) private String orderNumber;
    @Enumerated(EnumType.STRING) @Column(nullable=false) private Status status;
    @Column(name="origin_name", nullable=false) private String originName;
    @Column(name="origin_lat", nullable=false) private double originLat;
    @Column(name="origin_lon", nullable=false) private double originLon;
    @Column(name="destination_name", nullable=false) private String destinationName;
    @Column(name="destination_lat", nullable=false) private double destinationLat;
    @Column(name="destination_lon", nullable=false) private double destinationLon;
    @Column(name="idempotency_key", nullable=false, unique=true) private String idempotencyKey;
    @Column(name="created_at", nullable=false) private Instant createdAt;
    @Column(name="updated_at", nullable=false) private Instant updatedAt;

    protected CustomerOrder() {}

    public static CustomerOrder create(CreateOrderRequest request, String idempotencyKey) {
        var order = new CustomerOrder();
        var now = Instant.now();
        order.id = UUID.randomUUID();
        order.orderNumber = request.orderNumber();
        order.status = Status.READY;
        order.originName = request.origin().name();
        order.originLat = request.origin().lat();
        order.originLon = request.origin().lon();
        order.destinationName = request.destination().name();
        order.destinationLat = request.destination().lat();
        order.destinationLon = request.destination().lon();
        order.idempotencyKey = idempotencyKey;
        order.createdAt = now;
        order.updatedAt = now;
        return order;
    }

    public void dispatched() {
        if (status != Status.READY) throw new IllegalStateException("Only ready orders can be dispatched");
        status = Status.DISPATCHED;
        updatedAt = Instant.now();
    }

    public void fulfilled() {
        if (status == Status.FULFILLED) return;
        if (status != Status.DISPATCHED) throw new IllegalStateException("Only dispatched orders can be fulfilled");
        status = Status.FULFILLED;
        updatedAt = Instant.now();
    }

    public UUID getId(){return id;} public String getOrderNumber(){return orderNumber;} public Status getStatus(){return status;}
    public String getOriginName(){return originName;} public double getOriginLat(){return originLat;} public double getOriginLon(){return originLon;}
    public String getDestinationName(){return destinationName;} public double getDestinationLat(){return destinationLat;} public double getDestinationLon(){return destinationLon;}
    public Instant getCreatedAt(){return createdAt;} public Instant getUpdatedAt(){return updatedAt;}

    public enum Status { READY, DISPATCHED, FULFILLED }
}
