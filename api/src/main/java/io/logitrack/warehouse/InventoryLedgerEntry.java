package io.logitrack.warehouse;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name="inventory_ledger")
public class InventoryLedgerEntry {
    @Id private UUID id;
    @Column(name="task_id",nullable=false) private UUID taskId;
    @Column(name="warehouse_id",nullable=false) private String warehouseId;
    @Column(nullable=false) private String sku;
    @Enumerated(EnumType.STRING) @Column(name="transaction_type",nullable=false) private Type transactionType;
    @Column(name="on_hand_delta",nullable=false) private int onHandDelta;
    @Column(name="reserved_delta",nullable=false) private int reservedDelta;
    @Column(name="on_hand_after",nullable=false) private int onHandAfter;
    @Column(name="reserved_after",nullable=false) private int reservedAfter;
    @Column(name="occurred_at",nullable=false) private Instant occurredAt;
    protected InventoryLedgerEntry(){}
    public InventoryLedgerEntry(WarehouseTask task,Type type,int onHandDelta,int reservedDelta,WarehouseStock stock){id=UUID.randomUUID();taskId=task.getId();warehouseId=task.getWarehouseId();sku=task.getSku();transactionType=type;this.onHandDelta=onHandDelta;this.reservedDelta=reservedDelta;onHandAfter=stock.getOnHand();reservedAfter=stock.getReserved();occurredAt=Instant.now();}
    public UUID getId(){return id;} public UUID getTaskId(){return taskId;} public String getWarehouseId(){return warehouseId;} public String getSku(){return sku;}
    public Type getTransactionType(){return transactionType;} public int getOnHandDelta(){return onHandDelta;} public int getReservedDelta(){return reservedDelta;}
    public int getOnHandAfter(){return onHandAfter;} public int getReservedAfter(){return reservedAfter;} public Instant getOccurredAt(){return occurredAt;}
    public enum Type { RECEIPT, PICK, DISPATCH }
}

