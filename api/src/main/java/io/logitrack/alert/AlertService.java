package io.logitrack.alert;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.delivery.Delivery;
import io.logitrack.event.EventEnvelope;
import io.logitrack.outbox.*;
import io.logitrack.route.RouteSnapshotRepository;
import io.logitrack.stream.DeliveryStream;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.*;
import java.util.*;

@Service
public class AlertService {
    static final double DEVIATION_OPEN_METERS=500; static final double DEVIATION_CLOSE_METERS=300;
    static final long DELAY_OPEN_SECONDS=600; static final long DELAY_CLOSE_SECONDS=300;
    private final DeliveryAlertRepository alerts; private final RouteSnapshotRepository routes;
    private final OutboxRepository outbox; private final ObjectMapper mapper; private final DeliveryStream stream;
    public AlertService(DeliveryAlertRepository alerts,RouteSnapshotRepository routes,OutboxRepository outbox,ObjectMapper mapper,DeliveryStream stream){this.alerts=alerts;this.routes=routes;this.outbox=outbox;this.mapper=mapper;this.stream=stream;}

    public void evaluate(Delivery delivery,String traceId){
        routes.findTopByDeliveryIdOrderByGeneratedAtDesc(delivery.getId()).ifPresent(route->{
            var deviation=RouteDeviationCalculator.distanceMeters(delivery.getCurrentLat(),delivery.getCurrentLon(),route.getGeometry());
            reconcile(delivery,DeliveryAlert.Type.ROUTE_DEVIATION,deviation,deviation>=DEVIATION_OPEN_METERS,deviation<=DEVIATION_CLOSE_METERS,
                deviation>=1500?DeliveryAlert.Severity.CRITICAL:DeliveryAlert.Severity.WARNING,DEVIATION_OPEN_METERS,
                String.format(Locale.ROOT,"계획 경로에서 %.0fm 이탈",deviation),traceId);
            var delaySeconds=delivery.getEta()==null?0:Duration.between(route.getPlannedEta(),delivery.getEta()).toSeconds();
            var delayed=delivery.getStatus()==Delivery.Status.DELAYED||delaySeconds>=DELAY_OPEN_SECONDS;
            reconcile(delivery,DeliveryAlert.Type.DELAY,Math.max(0,delaySeconds),delayed,
                delivery.getStatus()!=Delivery.Status.DELAYED&&delaySeconds<=DELAY_CLOSE_SECONDS,
                delaySeconds>=1800?DeliveryAlert.Severity.CRITICAL:DeliveryAlert.Severity.WARNING,DELAY_OPEN_SECONDS,
                delaySeconds>0?String.format(Locale.ROOT,"계획 ETA 대비 %d분 지연",delaySeconds/60):"운행 상태에서 지연 감지",traceId);
        });
    }
    @Transactional
    public DeliveryAlert acknowledge(UUID id,String actor,String traceId){
        var normalizedActor=actor==null?"":actor.trim();
        if(normalizedActor.isBlank()||normalizedActor.length()>120)throw new IllegalArgumentException("X-Operator must be 1-120 characters");
        var alert=alerts.findByIdForUpdate(id).orElseThrow(()->new NoSuchElementException("Delivery alert not found"));
        if(alert.acknowledge(normalizedActor))emit(alert,"ACKNOWLEDGED",traceId==null||traceId.isBlank()?UUID.randomUUID().toString():traceId);
        return alert;
    }
    private void reconcile(Delivery delivery,DeliveryAlert.Type type,double value,boolean shouldOpen,boolean shouldClose,
        DeliveryAlert.Severity severity,double threshold,String message,String traceId){
        var active=alerts.findByDeliveryIdAndAlertTypeAndStatus(delivery.getId(),type,DeliveryAlert.Status.ACTIVE);
        if(active.isEmpty()&&shouldOpen){var alert=alerts.save(new DeliveryAlert(delivery.getId(),type,severity,message,value,threshold));emit(alert,"OPENED",traceId);}
        else if(active.isPresent()&&shouldClose){var alert=active.get();alert.resolve(value);emit(alert,"RESOLVED",traceId);}
        else if(active.isPresent()&&shouldOpen){var alert=active.get();if(alert.observe(severity,message,value))emit(alert,"ESCALATED",traceId);}
    }
    private void emit(DeliveryAlert alert,String action,String traceId){
        try{
            Map<String,Object> values=new LinkedHashMap<>();
            values.put("alertId",alert.getId());values.put("deliveryId",alert.getDeliveryId());values.put("alertType",alert.getAlertType());
            values.put("severity",alert.getSeverity());values.put("status",alert.getStatus());values.put("action",action);
            values.put("observedValue",alert.getObservedValue());values.put("message",alert.getMessage());
            if(alert.getAcknowledgedAt()!=null){values.put("acknowledgedAt",alert.getAcknowledgedAt());values.put("acknowledgedBy",alert.getAcknowledgedBy());}
            var payload=mapper.valueToTree(values);
            var event=new EventEnvelope(UUID.randomUUID(),"delivery.alert.v1",Instant.now(),traceId,1,payload);
            outbox.save(new OutboxEvent(event.eventId(),"DELIVERY_ALERT",alert.getId(),event.eventType(),"delivery.alert.v1",alert.getDeliveryId().toString(),mapper.writeValueAsString(event)));
            stream.publishAlert(alert);
        }catch(Exception error){throw new IllegalStateException("Could not publish alert event",error);}
    }
}
