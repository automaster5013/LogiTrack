package io.logitrack.replay;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.common.header.Headers;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;

@Component
public class DeadLetterCatalog {
    private final DeadLetterEventRepository repository;
    private final ObjectMapper mapper;

    public DeadLetterCatalog(DeadLetterEventRepository repository, ObjectMapper mapper) {
        this.repository = repository; this.mapper = mapper;
    }

    @KafkaListener(topics="vehicle.telemetry.dlq.v1", groupId="logitrack-dlq-catalog-v1",
        properties="auto.offset.reset=earliest")
    @Transactional
    public void capture(ConsumerRecord<String, String> record) {
        if (repository.existsByDlqTopicAndDlqPartitionAndDlqOffset(record.topic(), record.partition(), record.offset())) return;
        var originalTopic = header(record.headers(), "kafka_dlt-original-topic");
        if (originalTopic == null || originalTopic.isBlank()) originalTopic = "vehicle.telemetry.v1";
        var payload = record.value() == null ? "" : record.value();
        String traceId = null;
        try { traceId = mapper.readTree(payload).path("traceId").asText(null); } catch (Exception ignored) {}
        var event = new DeadLetterEvent(originalTopic, record.key(), payload, traceId,
            header(record.headers(), "kafka_dlt-exception-message"), record.topic(), record.partition(), record.offset());
        repository.saveAndFlush(event);
    }

    private String header(Headers headers, String key) {
        var header = headers.lastHeader(key);
        return header == null ? null : new String(header.value(), StandardCharsets.UTF_8);
    }
}
