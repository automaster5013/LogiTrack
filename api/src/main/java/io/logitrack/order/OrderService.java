package io.logitrack.order;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.delivery.*;
import io.logitrack.config.InputLimits;
import io.logitrack.event.EventEnvelope;
import io.logitrack.outbox.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.domain.*;

import java.time.Instant;
import java.util.*;

@Service
public class OrderService {
    private final CustomerOrderRepository orders;
    private final DeliveryRepository deliveries;
    private final DeliveryService deliveryService;
    private final OutboxRepository outbox;
    private final ObjectMapper mapper;

    public OrderService(CustomerOrderRepository orders, DeliveryRepository deliveries,
                        DeliveryService deliveryService, OutboxRepository outbox, ObjectMapper mapper) {
        this.orders=orders; this.deliveries=deliveries; this.deliveryService=deliveryService;
        this.outbox=outbox; this.mapper=mapper;
    }

    @Transactional
    public OrderSummary create(CreateOrderRequest request, String idempotencyKey, String traceId) {
        InputLimits.required(idempotencyKey,"Idempotency-Key",160);
        validate(request);
        var existing=orders.findByIdempotencyKey(idempotencyKey);
        if(existing.isPresent()){
            if(!matches(existing.get(),request))throw new IllegalStateException("Idempotency key was used with a different order request");
            return summary(existing.get(),deliveries.findByOrderId(existing.get().getId()).orElse(null));
        }
        var order=orders.save(CustomerOrder.create(request,idempotencyKey));
        saveEvent(order,"order.created.v1",traceId,Map.of("orderNumber",order.getOrderNumber(),"status",order.getStatus()));
        return summary(order,null);
    }

    @Transactional(readOnly=true)
    public List<OrderSummary> list(int limit) {
        var page=orders.findAll(PageRequest.of(0,limit,Sort.by(Sort.Direction.DESC,"createdAt"))).getContent();
        if(page.isEmpty())return List.of();
        var deliveryByOrder=deliveries.findByOrderIdIn(page.stream().map(CustomerOrder::getId).toList()).stream()
            .collect(java.util.stream.Collectors.toMap(Delivery::getOrderId,delivery->delivery));
        return page.stream().map(order->summary(order,deliveryByOrder.get(order.getId()))).toList();
    }

    @Transactional
    public OrderSummary dispatch(UUID orderId, DispatchOrderRequest request, String idempotencyKey, String traceId) {
        InputLimits.required(idempotencyKey,"Idempotency-Key",160);
        var order=orders.findForUpdateById(orderId).orElseThrow(()->new NoSuchElementException("Order not found"));
        var existing=deliveries.findByOrderId(orderId);
        if(request==null)throw new IllegalArgumentException("vehicleId is required");InputLimits.required(request.vehicleId(),"vehicleId",80);
        if(existing.isPresent()){
            if(!existing.get().getVehicleId().equals(request.vehicleId()))throw new IllegalStateException("Order was already dispatched to a different vehicle");
            return summary(order,existing.get());
        }
        if(order.getStatus()!=CustomerOrder.Status.READY) throw new IllegalStateException("Order is not ready for dispatch");
        var deliveryRequest=new CreateDeliveryRequest(order.getOrderNumber(),request.vehicleId(),
            new CreateDeliveryRequest.Location(order.getOriginName(),order.getOriginLat(),order.getOriginLon()),
            new CreateDeliveryRequest.Location(order.getDestinationName(),order.getDestinationLat(),order.getDestinationLon()));
        var delivery=deliveryService.createForOrder(orderId,deliveryRequest,idempotencyKey,traceId);
        order.dispatched();
        saveEvent(order,"order.dispatched.v1",traceId,Map.of("deliveryId",delivery.getId(),"vehicleId",delivery.getVehicleId(),"status",order.getStatus()));
        return summary(order,delivery);
    }

    @Transactional
    public void fulfillFromDelivery(Delivery delivery, String traceId) {
        if(delivery.getOrderId()==null||delivery.getStatus()!=Delivery.Status.DELIVERED) return;
        var order=orders.findById(delivery.getOrderId()).orElseThrow(()->new NoSuchElementException("Linked order not found"));
        if(order.getStatus()==CustomerOrder.Status.FULFILLED) return;
        order.fulfilled();
        saveEvent(order,"order.fulfilled.v1",traceId,Map.of("deliveryId",delivery.getId(),"status",order.getStatus()));
    }

    private OrderSummary summary(CustomerOrder order, Delivery delivery) {
        return new OrderSummary(order.getId(),order.getOrderNumber(),order.getStatus(),
            order.getOriginName(),order.getOriginLat(),order.getOriginLon(),
            order.getDestinationName(),order.getDestinationLat(),order.getDestinationLon(),
            delivery==null?null:delivery.getId(),delivery==null?null:delivery.getVehicleId(),
            delivery==null?null:delivery.getStatus(),order.getCreatedAt(),order.getUpdatedAt());
    }

    private void saveEvent(CustomerOrder order, String eventType, String traceId, Map<String,?> values) {
        try {
            var payload=new LinkedHashMap<String,Object>();
            payload.put("orderId",order.getId()); payload.put("orderNumber",order.getOrderNumber()); payload.putAll(values);
            var event=new EventEnvelope(UUID.randomUUID(),eventType,Instant.now(),traceId,1,mapper.valueToTree(payload));
            outbox.save(new OutboxEvent(event.eventId(),"ORDER",order.getId(),eventType,eventType,
                order.getId().toString(),mapper.writeValueAsString(event)));
        } catch(Exception error) {
            throw new IllegalStateException("Could not create order event",error);
        }
    }

    private void validate(CreateOrderRequest request) {
        if(request==null||request.origin()==null||request.destination()==null)
            throw new IllegalArgumentException("orderNumber, origin and destination are required");
        InputLimits.required(request.orderNumber(),"orderNumber",80);
        check(request.origin()); check(request.destination());
    }
    private void check(CreateOrderRequest.Location location) {
        InputLimits.required(location.name(),"location name",160);
        if(location.lat() < -90||location.lat()>90||location.lon() < -180||location.lon()>180)
            throw new IllegalArgumentException("Invalid order location");
    }
    private boolean matches(CustomerOrder order,CreateOrderRequest request){return order.getOrderNumber().equals(request.orderNumber())&&order.getOriginName().equals(request.origin().name())&&Double.compare(order.getOriginLat(),request.origin().lat())==0&&Double.compare(order.getOriginLon(),request.origin().lon())==0&&order.getDestinationName().equals(request.destination().name())&&Double.compare(order.getDestinationLat(),request.destination().lat())==0&&Double.compare(order.getDestinationLon(),request.destination().lon())==0;}
}
