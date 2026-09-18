package io.logitrack.warehouse;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class WarehouseStockTest {
 @Test void receiptPickAndDispatchPreserveInventoryInvariants(){var stock=new WarehouseStock("WH-SEOUL","SKU-001");stock.receive(10);assertEquals(10,stock.available());stock.pick(4);assertEquals(10,stock.getOnHand());assertEquals(4,stock.getReserved());assertEquals(6,stock.available());stock.dispatch(4);assertEquals(6,stock.getOnHand());assertEquals(0,stock.getReserved());}
 @Test void cannotPickMoreThanAvailable(){var stock=new WarehouseStock("WH-SEOUL","SKU-001");stock.receive(2);assertThrows(IllegalStateException.class,()->stock.pick(3));}
 @Test void cannotDispatchMoreThanReserved(){var stock=new WarehouseStock("WH-SEOUL","SKU-001");stock.receive(5);stock.pick(2);assertThrows(IllegalStateException.class,()->stock.dispatch(3));}
}
