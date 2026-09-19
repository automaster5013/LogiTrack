package io.logitrack.order;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.delivery.*;
import io.logitrack.outbox.*;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.*;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class OrderServiceTest {
    private final CustomerOrderRepository orders=mock(CustomerOrderRepository.class);
    private final DeliveryRepository deliveries=mock(DeliveryRepository.class);
    private final DeliveryService deliveryService=mock(DeliveryService.class);
    private final OutboxRepository outbox=mock(OutboxRepository.class);
    private final OrderService service=new OrderService(orders,deliveries,deliveryService,outbox,
        new ObjectMapper().findAndRegisterModules());

    @Test
    void createsIndependentOrderAndOutboxEvent() {
        when(orders.findByIdempotencyKey("order-key")).thenReturn(Optional.empty());
        when(orders.save(any())).thenAnswer(call->call.getArgument(0));

        var created=service.create(request(),"order-key","trace-1");

        assertEquals(CustomerOrder.Status.READY,created.status());
        assertNull(created.deliveryId());
        var event=ArgumentCaptor.forClass(OutboxEvent.class);
        verify(outbox).save(event.capture());
        assertEquals("order.created.v1",event.getValue().getTopic());
        verify(orders).lockIdempotencyKey("order-key");
    }

    @Test void sameIdempotencyKeyRejectsDifferentOrderRequest(){
        var existing=CustomerOrder.create(request(),"order-key");when(orders.findByIdempotencyKey("order-key")).thenReturn(Optional.of(existing));
        var changed=new CreateOrderRequest("ORD-CHANGED",request().origin(),request().destination());
        assertThrows(IllegalStateException.class,()->service.create(changed,"order-key","trace"));verifyNoInteractions(outbox);
    }

    @Test void rejectsOversizedIdempotencyKeyBeforeLookup(){
        assertThrows(IllegalArgumentException.class,()->service.create(request(),"K".repeat(161),"trace"));
        verifyNoInteractions(orders,deliveries,outbox);
    }

    @Test void rejectsNonFiniteCoordinatesBeforeLookup(){
        var bad=new CreateOrderRequest("ORD-1",new CreateOrderRequest.Location("X",0,Double.POSITIVE_INFINITY),request().destination());
        assertThrows(IllegalArgumentException.class,()->service.create(bad,"order-key","trace"));
        verifyNoInteractions(orders,deliveries,outbox);
    }

    @Test
    void dispatchCreatesOneLinkedDeliveryAndIsIdempotent() {
        var order=CustomerOrder.create(request(),"order-key");
        var delivery=Delivery.create(new CreateDeliveryRequest(order.getOrderNumber(),"TRUCK-1",
            new CreateDeliveryRequest.Location("Seoul",37.5665,126.978),
            new CreateDeliveryRequest.Location("Incheon",37.4563,126.7052)),"dispatch-key",order.getId());
        when(orders.findForUpdateById(order.getId())).thenReturn(Optional.of(order));
        when(deliveries.findByOrderId(order.getId())).thenReturn(Optional.empty(),Optional.of(delivery));
        when(deliveryService.createForOrder(eq(order.getId()),any(),eq("dispatch-key"),eq("trace-2"))).thenReturn(delivery);

        var first=service.dispatch(order.getId(),new DispatchOrderRequest("TRUCK-1"),"dispatch-key","trace-2");
        var second=service.dispatch(order.getId(),new DispatchOrderRequest("TRUCK-1"),"dispatch-key","trace-2");

        assertEquals(CustomerOrder.Status.DISPATCHED,first.status());
        assertEquals(delivery.getId(),second.deliveryId());
        verify(deliveryService,times(1)).createForOrder(eq(order.getId()),any(),eq("dispatch-key"),eq("trace-2"));
    }

    @Test
    void deliveredShipmentFulfillsLinkedOrder() {
        var order=CustomerOrder.create(request(),"order-key"); order.dispatched();
        var delivery=Delivery.create(new CreateDeliveryRequest(order.getOrderNumber(),"TRUCK-1",
            new CreateDeliveryRequest.Location("Seoul",37.5665,126.978),
            new CreateDeliveryRequest.Location("Incheon",37.4563,126.7052)),"dispatch-key",order.getId());
        delivery.applyTelemetry(37.4563,126.7052,1,null,Delivery.Status.DELIVERED);
        when(orders.findById(order.getId())).thenReturn(Optional.of(order));

        service.fulfillFromDelivery(delivery,"trace-3");

        assertEquals(CustomerOrder.Status.FULFILLED,order.getStatus());
        var event=ArgumentCaptor.forClass(OutboxEvent.class); verify(outbox).save(event.capture());
        assertEquals("order.fulfilled.v1",event.getValue().getTopic());
    }

    @Test void listsBoundedOrdersAndBatchLoadsLinkedDeliveries(){
        var first=CustomerOrder.create(request(),"order-key-1");
        var second=CustomerOrder.create(new CreateOrderRequest("ORD-2",request().origin(),request().destination()),"order-key-2");
        var linked=Delivery.create(new CreateDeliveryRequest(first.getOrderNumber(),"TRUCK-1",
            new CreateDeliveryRequest.Location("Seoul",37.5665,126.978),new CreateDeliveryRequest.Location("Incheon",37.4563,126.7052)),"dispatch-key",first.getId());
        var pageable=PageRequest.of(0,25,Sort.by(Sort.Direction.DESC,"createdAt"));
        when(orders.findAll(pageable)).thenReturn(new PageImpl<>(List.of(first,second)));
        when(deliveries.findByOrderIdIn(any())).thenReturn(List.of(linked));
        var result=service.list(25);
        assertEquals(linked.getId(),result.get(0).deliveryId());assertNull(result.get(1).deliveryId());
        verify(deliveries).findByOrderIdIn(List.of(first.getId(),second.getId()));
        verify(deliveries,never()).findByOrderId(any());
    }

    private CreateOrderRequest request() {
        return new CreateOrderRequest("ORD-1",new CreateOrderRequest.Location("Seoul",37.5665,126.978),
            new CreateOrderRequest.Location("Incheon",37.4563,126.7052));
    }
}
