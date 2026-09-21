package io.logitrack.warehouse;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.outbox.OutboxRepository;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.*;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WarehouseServiceTest {
 private final WarehouseStockRepository stocks=mock(WarehouseStockRepository.class);
 private final WarehouseTaskRepository tasks=mock(WarehouseTaskRepository.class);
 private final InventoryLedgerRepository ledger=mock(InventoryLedgerRepository.class);
 private final WarehouseService service=new WarehouseService(stocks,tasks,ledger,mock(OutboxRepository.class),new ObjectMapper());

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
