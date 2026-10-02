package io.logitrack.warehouse;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.outbox.OutboxRepository;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.*;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WarehouseServiceTest {
 private final WarehouseStockRepository stocks=mock(WarehouseStockRepository.class);
 private final WarehouseTaskRepository tasks=mock(WarehouseTaskRepository.class);
 private final InventoryLedgerRepository ledger=mock(InventoryLedgerRepository.class);
 private final OutboxRepository outbox=mock(OutboxRepository.class);
 private final WarehouseService service=new WarehouseService(stocks,tasks,ledger,outbox,new ObjectMapper().findAndRegisterModules());

 @Test void keyedDispatchReturnsOnlyTheMatchingStoredResult(){
  var command=new WarehouseCommand("OUT-1","WH-1","SKU-1",4);var task=WarehouseTask.outbound(command,"pick-key");
  var stock=new WarehouseStock("WH-1","SKU-1");stock.receive(10);stock.pick(4);
  when(tasks.findByDispatchRequestKey("dispatch-key")).thenReturn(Optional.empty(),Optional.of(task));
  when(tasks.findForUpdateById(task.getId())).thenReturn(Optional.of(task));when(stocks.lockByWarehouseAndSku("WH-1","SKU-1")).thenReturn(Optional.of(stock));
  assertSame(task,service.dispatch(task.getId(),"trace","dispatch-key"));assertEquals(WarehouseTask.Status.DISPATCHED,task.getStatus());assertEquals("dispatch-key",task.getDispatchRequestKey());
  assertSame(task,service.dispatch(task.getId(),"other-trace","dispatch-key"));verify(tasks,times(2)).lockDispatchRequestKey("dispatch-key");verify(ledger,times(1)).save(any());verify(outbox,times(1)).save(any());
  assertThrows(IllegalStateException.class,()->service.dispatch(UUID.randomUUID(),"trace","dispatch-key"));
  when(tasks.findByDispatchRequestKey("new-key")).thenReturn(Optional.empty());
  assertThrows(IllegalStateException.class,()->service.dispatch(task.getId(),"trace","new-key"));
 }

 @Test void pagesAllWarehouseCollectionsWithStableOrdering(){
  when(stocks.findAll(any(Pageable.class))).thenReturn(new PageImpl<>(List.of(),PageRequest.of(1,25),51));
  when(tasks.findAll(any(Pageable.class))).thenReturn(new PageImpl<>(List.of(),PageRequest.of(2,30),91));
  when(ledger.findAll(any(Pageable.class))).thenReturn(new PageImpl<>(List.of(),PageRequest.of(3,40),161));

  var stockPage=service.stockPage(1,25);var taskPage=service.taskPage(2,30);var ledgerPage=service.ledgerPage(3,40);

  assertEquals(51,stockPage.totalElements());assertTrue(stockPage.hasMore());
  assertEquals(91,taskPage.totalElements());assertTrue(taskPage.hasMore());
  assertEquals(161,ledgerPage.totalElements());assertTrue(ledgerPage.hasMore());
  var stockRequest=ArgumentCaptor.forClass(Pageable.class);var taskRequest=ArgumentCaptor.forClass(Pageable.class);var ledgerRequest=ArgumentCaptor.forClass(Pageable.class);
  verify(stocks).findAll(stockRequest.capture());verify(tasks).findAll(taskRequest.capture());verify(ledger).findAll(ledgerRequest.capture());
  assertEquals(Sort.Direction.ASC,stockRequest.getValue().getSort().getOrderFor("warehouseId").getDirection());
  assertEquals(Sort.Direction.ASC,stockRequest.getValue().getSort().getOrderFor("sku").getDirection());
  assertEquals(Sort.Direction.ASC,stockRequest.getValue().getSort().getOrderFor("id").getDirection());
  assertNewestFirst(taskRequest.getValue(),"createdAt");assertNewestFirst(ledgerRequest.getValue(),"occurredAt");
 }

 private void assertNewestFirst(Pageable request,String timestamp){
  assertEquals(Sort.Direction.DESC,request.getSort().getOrderFor(timestamp).getDirection());
  assertEquals(Sort.Direction.DESC,request.getSort().getOrderFor("id").getDirection());
 }
}
