package io.logitrack.warehouse;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.event.EventEnvelope;
import io.logitrack.config.InputLimits;
import io.logitrack.outbox.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.Instant;
import java.util.*;

@Service
public class WarehouseService {
 private final WarehouseStockRepository stocks; private final WarehouseTaskRepository tasks; private final InventoryLedgerRepository ledger; private final OutboxRepository outbox; private final ObjectMapper mapper;
 public WarehouseService(WarehouseStockRepository stocks,WarehouseTaskRepository tasks,InventoryLedgerRepository ledger,OutboxRepository outbox,ObjectMapper mapper){this.stocks=stocks;this.tasks=tasks;this.ledger=ledger;this.outbox=outbox;this.mapper=mapper;}

 @Transactional public WarehouseTask receive(WarehouseCommand command,String key,String traceId){
  validate(command,key);var existing=tasks.findByIdempotencyKey(key);if(existing.isPresent())return existing.get();
  var stock=lockedStock(command);stock.receive(command.quantity());var task=tasks.save(WarehouseTask.receipt(command,key));stocks.save(stock);
  ledger.save(new InventoryLedgerEntry(task,InventoryLedgerEntry.Type.RECEIPT,command.quantity(),0,stock));event(task,stock,"inventory.received.v1",traceId);return task;
 }
 @Transactional public WarehouseTask pick(WarehouseCommand command,String key,String traceId){
  validate(command,key);var existing=tasks.findByIdempotencyKey(key);if(existing.isPresent())return existing.get();
  var stock=stocks.lockByWarehouseAndSku(command.warehouseId(),command.sku()).orElseThrow(()->new IllegalStateException("Stock not found"));stock.pick(command.quantity());
  var task=tasks.save(WarehouseTask.outbound(command,key));ledger.save(new InventoryLedgerEntry(task,InventoryLedgerEntry.Type.PICK,0,command.quantity(),stock));event(task,stock,"warehouse.outbound.picked.v1",traceId);return task;
 }
 @Transactional public WarehouseTask dispatch(UUID id,String traceId){
  var task=tasks.findById(id).orElseThrow(()->new NoSuchElementException("Warehouse task not found"));if(task.getStatus()==WarehouseTask.Status.DISPATCHED)return task;
  var stock=stocks.lockByWarehouseAndSku(task.getWarehouseId(),task.getSku()).orElseThrow();stock.dispatch(task.getQuantity());task.dispatch();
  ledger.save(new InventoryLedgerEntry(task,InventoryLedgerEntry.Type.DISPATCH,-task.getQuantity(),-task.getQuantity(),stock));event(task,stock,"warehouse.outbound.dispatched.v1",traceId);return task;
 }
 public List<WarehouseStock> stock(){return stocks.findAllByOrderByWarehouseIdAscSkuAsc();} public List<WarehouseTask> tasks(){return tasks.findAllByOrderByCreatedAtDesc();} public List<InventoryLedgerEntry> ledger(){return ledger.findTop100ByOrderByOccurredAtDesc();}
 private WarehouseStock lockedStock(WarehouseCommand c){return stocks.lockByWarehouseAndSku(c.warehouseId(),c.sku()).orElseGet(()->new WarehouseStock(c.warehouseId(),c.sku()));}
 private void validate(WarehouseCommand c,String key){
  if(c==null||c.quantity()<=0)throw new IllegalArgumentException("referenceNumber, warehouseId, sku and positive quantity are required");
  InputLimits.required(c.referenceNumber(),"referenceNumber",100);InputLimits.required(c.warehouseId(),"warehouseId",80);InputLimits.required(c.sku(),"sku",100);InputLimits.required(key,"Idempotency-Key",160);
 }
 private void event(WarehouseTask task,WarehouseStock stock,String type,String traceId){try{var payload=mapper.valueToTree(Map.of("taskId",task.getId(),"warehouseId",task.getWarehouseId(),"sku",task.getSku(),"quantity",task.getQuantity(),"status",task.getStatus(),"onHand",stock.getOnHand(),"reserved",stock.getReserved()));var e=new EventEnvelope(UUID.randomUUID(),type,Instant.now(),traceId,1,payload);outbox.save(new OutboxEvent(e.eventId(),"WAREHOUSE_TASK",task.getId(),type,type,task.getWarehouseId()+":"+task.getSku(),mapper.writeValueAsString(e)));}catch(Exception e){throw new IllegalStateException("Could not create warehouse event",e);}}
}
