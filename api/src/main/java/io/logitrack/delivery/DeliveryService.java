package io.logitrack.delivery;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.event.EventEnvelope;
import io.logitrack.config.InputLimits;
import io.logitrack.outbox.*;
import io.logitrack.route.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.domain.*;
import java.time.Instant;
import java.util.*;

@Service
public class DeliveryService {
    private final DeliveryRepository repository; private final OutboxRepository outbox; private final ObjectMapper mapper;
    private final RouteAnalysisClient routeAnalysis; private final RouteSnapshotRepository routes;
    public DeliveryService(DeliveryRepository repository, OutboxRepository outbox, ObjectMapper mapper,
        RouteAnalysisClient routeAnalysis,RouteSnapshotRepository routes){this.repository=repository;this.outbox=outbox;this.mapper=mapper;this.routeAnalysis=routeAnalysis;this.routes=routes;}

    @Transactional
    public Delivery create(CreateDeliveryRequest request, String key, String traceId) {
        return create(request,key,traceId,null);
    }
    @Transactional
    public Delivery createForOrder(UUID orderId, CreateDeliveryRequest request, String key, String traceId) {
        return create(request,key,traceId,orderId);
    }
    private Delivery create(CreateDeliveryRequest request, String key, String traceId, UUID orderId) {
        InputLimits.required(key,"Idempotency-Key",160);
        validate(request);
        repository.lockIdempotencyKey(key);
        var existing=repository.findByIdempotencyKey(key);
        if(existing.isPresent()) {
            if(orderId!=null&&!orderId.equals(existing.get().getOrderId()))
                throw new IllegalStateException("Idempotency key belongs to another order");
            if(!matches(existing.get(),request))throw new IllegalStateException("Idempotency key was used with a different delivery request");
            return existing.get();
        }
        if(orderId!=null){var linked=repository.findByOrderId(orderId);if(linked.isPresent())return linked.get();}
        var saved=repository.save(Delivery.create(request,key,orderId));
        var route=routeAnalysis.analyze(saved);
        try {
            var geometry=mapper.valueToTree(Map.of("type","LineString","coordinates",route.coordinates()));
            routes.save(new RouteSnapshot(saved,route,geometry));
            var payloadValues=new LinkedHashMap<String,Object>();
            payloadValues.put("deliveryId",saved.getId());payloadValues.put("orderId",saved.getOrderId());payloadValues.put("orderNumber",saved.getOrderNumber());payloadValues.put("vehicleId",saved.getVehicleId());
            payloadValues.put("origin",Map.of("lat",saved.getOriginLat(),"lon",saved.getOriginLon()));
            payloadValues.put("destination",Map.of("lat",saved.getDestinationLat(),"lon",saved.getDestinationLon()));
            payloadValues.put("route",route.coordinates());payloadValues.put("routeProvider",route.provider());
            payloadValues.put("distanceMeters",route.distanceMeters());payloadValues.put("plannedDurationSeconds",route.durationSeconds());
            payloadValues.put("plannedEta",route.plannedEta().toString());
            var payload=mapper.valueToTree(payloadValues);
            var event=new EventEnvelope(UUID.randomUUID(),"delivery.created.v1",Instant.now(),traceId,1,payload);
            outbox.save(new OutboxEvent(event.eventId(),"DELIVERY",saved.getId(),event.eventType(),
                "delivery.created.v1",saved.getId().toString(),mapper.writeValueAsString(event)));
        } catch(Exception e){throw new IllegalStateException("Could not publish delivery event",e);}
        return saved;
    }
    @Transactional(readOnly=true)
    public List<Delivery> list(int limit){return repository.findAll(PageRequest.of(0,limit,stableSort())).getContent();}
    @Transactional(readOnly=true)
    public DeliveryPage page(int page,int size){
        var pageable=PageRequest.of(page,size,stableSort());
        var result=repository.findAll(pageable);
        return new DeliveryPage(result.getContent(),result.getNumber(),result.getSize(),result.getTotalElements(),result.hasNext());
    }
    @Transactional(readOnly=true)
    public Delivery get(UUID id){return repository.findById(id).orElseThrow(()->new NoSuchElementException("Delivery not found"));}
    public record DeliveryPage(List<Delivery> items,int page,int size,long totalElements,boolean hasMore){}
    private Sort stableSort(){return Sort.by(Sort.Direction.DESC,"createdAt").and(Sort.by(Sort.Direction.DESC,"id"));}
    private void validate(CreateDeliveryRequest r){
        if(r==null||r.origin()==null||r.destination()==null)throw new IllegalArgumentException("orderNumber, vehicleId, origin and destination are required");
        InputLimits.required(r.orderNumber(),"orderNumber",80);InputLimits.required(r.vehicleId(),"vehicleId",80);
        check(r.origin()); check(r.destination());
    }
    private void check(CreateDeliveryRequest.Location p){InputLimits.required(p.name(),"location name",160);if(!Double.isFinite(p.lat())||!Double.isFinite(p.lon())||p.lat() < -90||p.lat()>90||p.lon() < -180||p.lon()>180) throw new IllegalArgumentException("Invalid coordinates");}
    private boolean matches(Delivery d,CreateDeliveryRequest r){return d.getOrderNumber().equals(r.orderNumber())&&d.getVehicleId().equals(r.vehicleId())&&d.getOriginName().equals(r.origin().name())&&Double.compare(d.getOriginLat(),r.origin().lat())==0&&Double.compare(d.getOriginLon(),r.origin().lon())==0&&d.getDestinationName().equals(r.destination().name())&&Double.compare(d.getDestinationLat(),r.destination().lat())==0&&Double.compare(d.getDestinationLon(),r.destination().lon())==0;}
}
