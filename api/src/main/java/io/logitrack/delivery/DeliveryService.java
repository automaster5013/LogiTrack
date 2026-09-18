package io.logitrack.delivery;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.event.EventEnvelope;
import io.logitrack.outbox.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.Instant;
import java.util.*;

@Service
public class DeliveryService {
    private final DeliveryRepository repository; private final OutboxRepository outbox; private final ObjectMapper mapper;
    public DeliveryService(DeliveryRepository repository, OutboxRepository outbox, ObjectMapper mapper){this.repository=repository;this.outbox=outbox;this.mapper=mapper;}

    @Transactional
    public Delivery create(CreateDeliveryRequest request, String key, String traceId) {
        var existing=repository.findByIdempotencyKey(key); if(existing.isPresent()) return existing.get();
        validate(request);
        var saved=repository.save(Delivery.create(request,key));
        try {
            var payload=mapper.valueToTree(Map.of("deliveryId",saved.getId(),"vehicleId",saved.getVehicleId(),
                "origin",Map.of("lat",saved.getOriginLat(),"lon",saved.getOriginLon()),
                "destination",Map.of("lat",saved.getDestinationLat(),"lon",saved.getDestinationLon())));
            var event=new EventEnvelope(UUID.randomUUID(),"delivery.created.v1",Instant.now(),traceId,1,payload);
            outbox.save(new OutboxEvent(event.eventId(),"DELIVERY",saved.getId(),event.eventType(),
                "delivery.created.v1",saved.getId().toString(),mapper.writeValueAsString(event)));
        } catch(Exception e){throw new IllegalStateException("Could not publish delivery event",e);}
        return saved;
    }
    public List<Delivery> list(){return repository.findAll();}
    private void validate(CreateDeliveryRequest r){
        if(r==null||blank(r.orderNumber())||blank(r.vehicleId())||r.origin()==null||r.destination()==null) throw new IllegalArgumentException("orderNumber, vehicleId, origin and destination are required");
        check(r.origin()); check(r.destination());
    }
    private void check(CreateDeliveryRequest.Location p){if(p.lat() < -90||p.lat()>90||p.lon() < -180||p.lon()>180) throw new IllegalArgumentException("Invalid coordinates");}
    private boolean blank(String s){return s==null||s.isBlank();}
}
