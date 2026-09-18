package io.logitrack.warehouse;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name="warehouse_stock",uniqueConstraints=@UniqueConstraint(columnNames={"warehouse_id","sku"}))
public class WarehouseStock {
    @Id private UUID id;
    @Column(name="warehouse_id",nullable=false) private String warehouseId;
    @Column(nullable=false) private String sku;
    @Column(name="on_hand",nullable=false) private int onHand;
    @Column(nullable=false) private int reserved;
    @Version private long version;
    @Column(name="updated_at",nullable=false) private Instant updatedAt;
    protected WarehouseStock(){}
    public WarehouseStock(String warehouseId,String sku){this.id=UUID.randomUUID();this.warehouseId=warehouseId;this.sku=sku;this.updatedAt=Instant.now();}
    public void receive(int quantity){onHand=Math.addExact(onHand,quantity);touch();}
    public void pick(int quantity){if(available()<quantity)throw new IllegalStateException("Insufficient available stock");reserved=Math.addExact(reserved,quantity);touch();}
    public void dispatch(int quantity){if(reserved<quantity)throw new IllegalStateException("Insufficient reserved stock");reserved-=quantity;onHand-=quantity;touch();}
    private void touch(){updatedAt=Instant.now();}
    public int available(){return onHand-reserved;}
    public UUID getId(){return id;} public String getWarehouseId(){return warehouseId;} public String getSku(){return sku;}
    public int getOnHand(){return onHand;} public int getReserved(){return reserved;} public int getAvailable(){return available();} public Instant getUpdatedAt(){return updatedAt;}
}
