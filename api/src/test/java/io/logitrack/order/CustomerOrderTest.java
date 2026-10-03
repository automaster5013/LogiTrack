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

    @Test
    void dispatchCannotRepeatAndFulfillmentIsIdempotent() {
        var order=CustomerOrder.create(request(),"order-repeat-key");
        order.dispatched();
        assertThrows(IllegalStateException.class,order::dispatched);
        order.fulfilled();
        var fulfilledAt=order.getUpdatedAt();

        order.fulfilled();

        assertEquals(CustomerOrder.Status.FULFILLED,order.getStatus());
        assertEquals(fulfilledAt,order.getUpdatedAt());
    }

    @Test
    void persistsDispatchRequestIdentity() {
        var order=CustomerOrder.create(request(),"order-key");

        order.dispatched("dispatch-key");

        assertEquals("dispatch-key",order.getDispatchRequestKey());
        assertThrows(IllegalStateException.class,()->order.bindDispatchRequestKey("another-key"));
    }

    @Test
    void legacyDispatchedOrderCanBindOneRequestIdentity() {
        var order=CustomerOrder.create(request(),"order-key");
        assertThrows(IllegalStateException.class,()->order.bindDispatchRequestKey("too-early"));
        order.dispatched();

        order.bindDispatchRequestKey("claimed-key");

        assertEquals("claimed-key",order.getDispatchRequestKey());
        assertThrows(IllegalStateException.class,()->order.bindDispatchRequestKey("replacement-key"));
    }

    private CreateOrderRequest request() {
        return new CreateOrderRequest("ORD-1",new CreateOrderRequest.Location("Seoul",37.5665,126.978),
            new CreateOrderRequest.Location("Incheon",37.4563,126.7052));
    }
}
