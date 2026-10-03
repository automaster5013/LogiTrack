package io.logitrack.replay;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.common.header.internals.RecordHeader;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.kafka.annotation.KafkaListener;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class DeadLetterCatalogTest {
    @Test
    void catalogsTelemetryAndSimulatorDeadLetterTopics() throws Exception {
        var method = DeadLetterCatalog.class.getDeclaredMethod("capture", ConsumerRecord.class);
        var listener = method.getAnnotation(KafkaListener.class);

        assertThat(listener.topics()).containsExactlyInAnyOrder(
            "vehicle.telemetry.dlq.v1", "delivery.created.dlq.v1"
        );
    }

    @Test
    void capturesAsciiSimulatorSourcePosition() {
        var repository = mock(DeadLetterEventRepository.class);
        var record = record("delivery.created.dlq.v1",11);
        record.headers().add(header("kafka_dlt-original-topic","delivery.created.v1"));
        record.headers().add(header("kafka_dlt-original-partition","2"));
        record.headers().add(header("kafka_dlt-original-offset","41"));

        new DeadLetterCatalog(repository,new ObjectMapper()).capture(record);

        var captor = ArgumentCaptor.forClass(DeadLetterEvent.class);
        verify(repository).saveAndFlush(captor.capture());
        var event = captor.getValue();
        assertThat(event.getOriginalTopic()).isEqualTo("delivery.created.v1");
        assertThat(event.getOriginalPartition()).isEqualTo(2);
        assertThat(event.getOriginalOffset()).isEqualTo(41L);
    }

    @Test
    void capturesBinarySpringSourcePosition() {
        var repository = mock(DeadLetterEventRepository.class);
        var record = record("vehicle.telemetry.dlq.v1",12);
        record.headers().add(header("kafka_dlt-original-topic","vehicle.telemetry.v1"));
        record.headers().add(new RecordHeader("kafka_dlt-original-partition",ByteBuffer.allocate(4).putInt(1).array()));
        record.headers().add(new RecordHeader("kafka_dlt-original-offset",ByteBuffer.allocate(8).putLong(99).array()));

        new DeadLetterCatalog(repository,new ObjectMapper()).capture(record);

        var captor = ArgumentCaptor.forClass(DeadLetterEvent.class);
        verify(repository).saveAndFlush(captor.capture());
        var event = captor.getValue();
        assertThat(event.getOriginalPartition()).isEqualTo(1);
        assertThat(event.getOriginalOffset()).isEqualTo(99L);
    }

    @Test
    void ignoresASecondDlqRecordForTheSameSourcePosition() {
        var repository = mock(DeadLetterEventRepository.class);
        when(repository.existsByOriginalTopicAndOriginalPartitionAndOriginalOffset(
            "delivery.created.v1",2,41L)).thenReturn(true);
        var record = record("delivery.created.dlq.v1",99);
        record.headers().add(header("kafka_dlt-original-topic","delivery.created.v1"));
        record.headers().add(header("kafka_dlt-original-partition","2"));
        record.headers().add(header("kafka_dlt-original-offset","41"));

        new DeadLetterCatalog(repository,new ObjectMapper()).capture(record);

        verify(repository,never()).saveAndFlush(any());
    }

    @Test
    void ignoresAnIncompleteSourcePositionWithoutRejectingTheDlqRecord() {
        var repository = mock(DeadLetterEventRepository.class);
        var record = record("delivery.created.dlq.v1",13);
        record.headers().add(header("kafka_dlt-original-topic","delivery.created.v1"));
        record.headers().add(header("kafka_dlt-original-partition","2"));

        new DeadLetterCatalog(repository,new ObjectMapper()).capture(record);

        var captor = ArgumentCaptor.forClass(DeadLetterEvent.class);
        verify(repository).saveAndFlush(captor.capture());
        assertThat(captor.getValue().getOriginalPartition()).isNull();
        assertThat(captor.getValue().getOriginalOffset()).isNull();
    }

    private ConsumerRecord<String,String> record(String topic,long offset) {
        return new ConsumerRecord<>(topic,0,offset,"key","{\"traceId\":\"trace\"}");
    }

    private RecordHeader header(String name,String value) {
        return new RecordHeader(name,value.getBytes(StandardCharsets.UTF_8));
    }
}
