package io.logitrack.order;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class CustomerOrderTest {
    @Test
    void transitionsFromReadyToDispatchedToFulfilled() {
        var order=CustomerOrder.create(request(),"order-key");
        assertEquals(CustomerOrder.Status.READY,order.getStatus());
        order.dispatched();
        assertEquals(CustomerOrder.Status.DISPATCHED,order.getStatus());
        order.fulfilled();
        assertEquals(CustomerOrder.Status.FULFILLED,order.getStatus());
    }

    @Test
    void cannotFulfillBeforeDispatch() {
        var order=CustomerOrder.create(request(),"order-key");
        assertThrows(IllegalStateException.class,order::fulfilled);
    }

    private CreateOrderRequest request() {
        return new CreateOrderRequest("ORD-1",new CreateOrderRequest.Location("Seoul",37.5665,126.978),
            new CreateOrderRequest.Location("Incheon",37.4563,126.7052));
    }
}
