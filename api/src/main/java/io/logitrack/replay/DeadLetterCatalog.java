package io.logitrack.replay;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.common.header.Headers;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

@Component
public class DeadLetterCatalog {
    private final DeadLetterEventRepository repository;
    private final ObjectMapper mapper;

    public DeadLetterCatalog(DeadLetterEventRepository repository, ObjectMapper mapper) {
        this.repository = repository; this.mapper = mapper;
    }

    @KafkaListener(topics={"vehicle.telemetry.dlq.v1", "delivery.created.dlq.v1"}, groupId="logitrack-dlq-catalog-v1",
        properties="auto.offset.reset=earliest")
    @Transactional
    public void capture(ConsumerRecord<String, String> record) {
        if (repository.existsByDlqTopicAndDlqPartitionAndDlqOffset(record.topic(), record.partition(), record.offset())) return;
        var originalTopic = header(record.headers(), "kafka_dlt-original-topic");
        if (originalTopic == null || originalTopic.isBlank()) originalTopic = "vehicle.telemetry.v1";
        var originalPartition = integerHeader(record.headers(), "kafka_dlt-original-partition");
        var originalOffset = longHeader(record.headers(), "kafka_dlt-original-offset");
        if (originalPartition == null || originalOffset == null) {
            originalPartition = null;
            originalOffset = null;
        }
        if (originalPartition != null && originalOffset != null &&
            repository.existsByOriginalTopicAndOriginalPartitionAndOriginalOffset(
                originalTopic, originalPartition, originalOffset)) return;
        var payload = record.value() == null ? "" : record.value();
        String traceId = null;
        try { traceId = mapper.readTree(payload).path("traceId").asText(null); } catch (Exception ignored) {}
        var event = new DeadLetterEvent(originalTopic, originalPartition, originalOffset, record.key(), payload, traceId,
            header(record.headers(), "kafka_dlt-exception-message"), record.topic(), record.partition(), record.offset());
        repository.saveAndFlush(event);
    }

    private String header(Headers headers, String key) {
        var header = headers.lastHeader(key);
        return header == null ? null : new String(header.value(), StandardCharsets.UTF_8);
    }

    private Integer integerHeader(Headers headers, String key) {
        var value = headerBytes(headers,key);
        if (value == null) return null;
        var ascii = new String(value,StandardCharsets.UTF_8);
        try { if (ascii.matches("[0-9]+")) return Integer.valueOf(ascii); }
        catch (NumberFormatException ignored) { return null; }
        if (value.length != Integer.BYTES) return null;
        var parsed = ByteBuffer.wrap(value).getInt();
        return parsed >= 0 ? parsed : null;
    }

    private Long longHeader(Headers headers, String key) {
        var value = headerBytes(headers,key);
        if (value == null) return null;
        var ascii = new String(value,StandardCharsets.UTF_8);
        try { if (ascii.matches("[0-9]+")) return Long.valueOf(ascii); }
        catch (NumberFormatException ignored) { return null; }
        if (value.length != Long.BYTES) return null;
        var parsed = ByteBuffer.wrap(value).getLong();
        return parsed >= 0 ? parsed : null;
    }

    private byte[] headerBytes(Headers headers, String key) {
        var header = headers.lastHeader(key);
        return header == null ? null : header.value();
    }
}
