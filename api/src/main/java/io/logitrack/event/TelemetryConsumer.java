package io.logitrack.event;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import io.logitrack.delivery.*;
import io.logitrack.alert.AlertService;
import io.logitrack.order.OrderService;
import io.logitrack.stream.DeliveryStream;
import io.logitrack.telemetry.*;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import java.time.Instant;
import java.util.UUID;

@Component
public class TelemetryConsumer {
    private final ObjectMapper mapper; private final DeliveryRepository deliveries; private final ProcessedEventRepository processed; private final DeliveryStream stream; private final AlertService alerts; private final OrderService orders; private final TelemetryPointRepository points;
    public TelemetryConsumer(ObjectMapper mapper,DeliveryRepository deliveries,ProcessedEventRepository processed,DeliveryStream stream,AlertService alerts,OrderService orders,TelemetryPointRepository points){this.mapper=mapper;this.deliveries=deliveries;this.processed=processed;this.stream=stream;this.alerts=alerts;this.orders=orders;this.points=points;}
    @KafkaListener(topics="vehicle.telemetry.v1") @Transactional
    public void consume(String raw) throws Exception {
        var event=mapper.readTree(raw); var id=UUID.fromString(event.required("eventId").asText()); if(processed.existsById(id)) return;
        if(!event.path("eventType").isTextual()||!"vehicle.telemetry.v1".equals(event.path("eventType").textValue()))throw new IllegalArgumentException("Invalid telemetry event type");
        if(!event.path("schemaVersion").isIntegralNumber()||event.path("schemaVersion").intValue()!=1)throw new IllegalArgumentException("Unsupported telemetry schema version");
        var p=event.required("payload"); var delivery=deliveries.findById(UUID.fromString(p.required("deliveryId").asText())).orElseThrow();
        var progress=number(p,"progress"); var status=Delivery.Status.valueOf(p.required("status").asText());
        var eta=p.hasNonNull("eta")?Instant.parse(p.get("eta").asText()):null;
        var lat=number(p,"lat"); var lon=number(p,"lon");
        var occurredAt=event.hasNonNull("occurredAt")?Instant.parse(event.get("occurredAt").asText()):Instant.now();
        var applied=delivery.applyTelemetry(lat,lon,progress,eta,status,occurredAt);
        var point=points.save(new TelemetryPoint(id,delivery,lat,lon,progress,occurredAt));
        if(applied){alerts.evaluate(delivery,event.path("traceId").asText(UUID.randomUUID().toString()));orders.fulfillFromDelivery(delivery,event.path("traceId").asText(UUID.randomUUID().toString()));}
        processed.save(new ProcessedEvent(id,"control-api-telemetry-v1"));if(applied)stream.publish(delivery);stream.publishTelemetry(point);
    }
    private double number(JsonNode payload,String field){var value=payload.required(field);if(!value.isNumber())throw new IllegalArgumentException(field+" must be a number");return value.doubleValue();}
}
