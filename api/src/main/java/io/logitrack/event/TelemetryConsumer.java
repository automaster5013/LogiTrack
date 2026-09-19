package io.logitrack.event;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import io.logitrack.delivery.*;
import io.logitrack.alert.AlertService;
import io.logitrack.order.OrderService;
import io.logitrack.stream.CommittedDeliveryStream;
import io.logitrack.telemetry.*;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import java.time.Instant;
import java.time.Duration;
import java.util.UUID;
import java.util.regex.Pattern;

@Component
public class TelemetryConsumer {
    private static final Pattern SAFE_TRACE=Pattern.compile("[A-Za-z0-9._:-]{1,128}");
    private final ObjectMapper mapper; private final DeliveryRepository deliveries; private final ProcessedEventRepository processed; private final CommittedDeliveryStream stream; private final AlertService alerts; private final OrderService orders; private final TelemetryPointRepository points;private final Duration maxFutureSkew;private final Counter appliedEvents;private final Counter staleEvents;
    public TelemetryConsumer(ObjectMapper mapper,DeliveryRepository deliveries,ProcessedEventRepository processed,CommittedDeliveryStream stream,AlertService alerts,OrderService orders,TelemetryPointRepository points,
        @Value("${logitrack.telemetry.max-future-skew:5m}") Duration maxFutureSkew,MeterRegistry metrics){if(maxFutureSkew.isNegative())throw new IllegalArgumentException("Telemetry future skew must not be negative");this.mapper=mapper;this.deliveries=deliveries;this.processed=processed;this.stream=stream;this.alerts=alerts;this.orders=orders;this.points=points;this.maxFutureSkew=maxFutureSkew;this.appliedEvents=metrics.counter("logitrack.telemetry.events","outcome","applied");this.staleEvents=metrics.counter("logitrack.telemetry.events","outcome","stale");}
    @KafkaListener(topics="vehicle.telemetry.v1") @Transactional
    public void consume(String raw) throws Exception {
        var event=mapper.readTree(raw); var id=UUID.fromString(event.required("eventId").asText()); if(processed.existsById(id)) return;
        if(!event.path("eventType").isTextual()||!"vehicle.telemetry.v1".equals(event.path("eventType").textValue()))throw new IllegalArgumentException("Invalid telemetry event type");
        if(!event.path("schemaVersion").isIntegralNumber()||event.path("schemaVersion").intValue()!=1)throw new IllegalArgumentException("Unsupported telemetry schema version");
        var traceId=event.hasNonNull("traceId")?event.path("traceId").asText(null):UUID.randomUUID().toString();
        if(traceId==null||!SAFE_TRACE.matcher(traceId).matches())throw new IllegalArgumentException("Invalid telemetry traceId");
        var p=event.required("payload"); var delivery=deliveries.findById(UUID.fromString(p.required("deliveryId").asText())).orElseThrow();
        if(!p.path("vehicleId").isTextual()||!delivery.getVehicleId().equals(p.path("vehicleId").textValue()))throw new IllegalArgumentException("Telemetry vehicle does not match delivery");
        var progress=number(p,"progress"); var status=Delivery.Status.valueOf(p.required("status").asText());
        var eta=p.hasNonNull("eta")?Instant.parse(p.get("eta").asText()):null;
        var lat=number(p,"lat"); var lon=number(p,"lon");
        if(!event.path("occurredAt").isTextual())throw new IllegalArgumentException("Telemetry occurredAt is required");
        var occurredAt=Instant.parse(event.path("occurredAt").textValue());
        if(occurredAt.isAfter(Instant.now().plus(maxFutureSkew)))throw new IllegalArgumentException("Telemetry occurredAt is too far in the future");
        var applied=delivery.applyTelemetry(lat,lon,progress,eta,status,occurredAt);
        (applied?appliedEvents:staleEvents).increment();
        var point=points.save(new TelemetryPoint(id,delivery,lat,lon,progress,occurredAt));
        if(applied){alerts.evaluate(delivery,traceId);orders.fulfillFromDelivery(delivery,traceId);}
        processed.save(new ProcessedEvent(id,"control-api-telemetry-v1"));if(applied)stream.publishDelivery(delivery);stream.publishTelemetry(point);
    }
    private double number(JsonNode payload,String field){var value=payload.required(field);if(!value.isNumber())throw new IllegalArgumentException(field+" must be a number");return value.doubleValue();}
}
