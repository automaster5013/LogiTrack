package io.logitrack.warehouse;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name="warehouse_tasks")
public class WarehouseTask {
    @Id private UUID id;
    @Enumerated(EnumType.STRING) @Column(name="task_type",nullable=false) private Type taskType;
    @Enumerated(EnumType.STRING) @Column(nullable=false) private Status status;
    @Column(name="reference_number",nullable=false) private String referenceNumber;
    @Column(name="warehouse_id",nullable=false) private String warehouseId;
    @Column(nullable=false) private String sku;
    @Column(nullable=false) private int quantity;
    @Column(name="idempotency_key",nullable=false,unique=true) private String idempotencyKey;
    @Column(name="created_at",nullable=false) private Instant createdAt;
    @Column(name="updated_at",nullable=false) private Instant updatedAt;
    protected WarehouseTask(){}
    public static WarehouseTask receipt(WarehouseCommand request,String key){return create(request,key,Type.INBOUND,Status.RECEIVED);}
    public static WarehouseTask outbound(WarehouseCommand request,String key){return create(request,key,Type.OUTBOUND,Status.PICKED);}
    private static WarehouseTask create(WarehouseCommand r,String key,Type type,Status status){var t=new WarehouseTask();var now=Instant.now();t.id=UUID.randomUUID();t.taskType=type;t.status=status;t.referenceNumber=r.referenceNumber();t.warehouseId=r.warehouseId();t.sku=r.sku();t.quantity=r.quantity();t.idempotencyKey=key;t.createdAt=now;t.updatedAt=now;return t;}
    public void dispatch(){if(status==Status.DISPATCHED)return;if(status!=Status.PICKED)throw new IllegalStateException("Only picked tasks can be dispatched");status=Status.DISPATCHED;updatedAt=Instant.now();}
    public UUID getId(){return id;} public Type getTaskType(){return taskType;} public Status getStatus(){return status;}
    public String getReferenceNumber(){return referenceNumber;} public String getWarehouseId(){return warehouseId;} public String getSku(){return sku;}
    public int getQuantity(){return quantity;} public Instant getCreatedAt(){return createdAt;} public Instant getUpdatedAt(){return updatedAt;}
    public enum Type { INBOUND, OUTBOUND } public enum Status { RECEIVED, PICKED, DISPATCHED }
}

