package io.logitrack.order;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class OrderControllerTest {
    @Test void rejectsInvalidPageAndSize(){
        var service=mock(OrderService.class);var controller=new OrderController(service);
        assertThrows(IllegalArgumentException.class,()->controller.page(-1,100));
        assertThrows(IllegalArgumentException.class,()->controller.page(0,0));
        verifyNoInteractions(service);
    }
}
