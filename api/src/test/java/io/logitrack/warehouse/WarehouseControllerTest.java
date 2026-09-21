package io.logitrack.warehouse;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WarehouseControllerTest {
 @Test void rejectsInvalidPagesAndSizesBeforeService(){
  var service=mock(WarehouseService.class);var controller=new WarehouseController(service);
  assertThrows(IllegalArgumentException.class,()->controller.stockPage(-1,100));
  assertThrows(IllegalArgumentException.class,()->controller.taskPage(0,0));
  assertThrows(IllegalArgumentException.class,()->controller.ledgerPage(0,501));
  verifyNoInteractions(service);
 }
}
