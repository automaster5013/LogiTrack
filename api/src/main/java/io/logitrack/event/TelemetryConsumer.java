package io.logitrack.event;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.delivery.*;
import io.logitrack.alert.AlertService;
import io.logitrack.order.OrderService;
import io.logitrack.stream.DeliveryStream;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import java.time.Instant;
import java.util.UUID;

@Component
public class TelemetryConsumer {
    private final ObjectMapper mapper; private final DeliveryRepository deliveries; private final ProcessedEventRepository processed; private final DeliveryStream stream; private final AlertService alerts; private final OrderService orders;
    public TelemetryConsumer(ObjectMapper mapper,DeliveryRepository deliveries,ProcessedEventRepository processed,DeliveryStream stream,AlertService alerts,OrderService orders){this.mapper=mapper;this.deliveries=deliveries;this.processed=processed;this.stream=stream;this.alerts=alerts;this.orders=orders;}
    @KafkaListener(topics="vehicle.telemetry.v1") @Transactional
    public void consume(String raw) throws Exception {
        var event=mapper.readTree(raw); var id=UUID.fromString(event.required("eventId").asText()); if(processed.existsById(id)) return;
        var p=event.required("payload"); var delivery=deliveries.findById(UUID.fromString(p.required("deliveryId").asText())).orElseThrow();
        var progress=p.required("progress").asDouble(); var status=Delivery.Status.valueOf(p.required("status").asText());
        var eta=p.hasNonNull("eta")?Instant.parse(p.get("eta").asText()):null;
        delivery.applyTelemetry(p.required("lat").asDouble(),p.required("lon").asDouble(),progress,eta,status);
        alerts.evaluate(delivery,event.path("traceId").asText(UUID.randomUUID().toString()));
        orders.fulfillFromDelivery(delivery,event.path("traceId").asText(UUID.randomUUID().toString()));
        processed.save(new ProcessedEvent(id,"control-api-telemetry-v1")); stream.publish(delivery);
    }
}
