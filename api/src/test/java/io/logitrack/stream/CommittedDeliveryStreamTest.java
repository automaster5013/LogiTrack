package io.logitrack.stream;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import java.util.Map;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class CommittedDeliveryStreamTest {
    @AfterEach void clear(){if(TransactionSynchronizationManager.isSynchronizationActive())TransactionSynchronizationManager.clearSynchronization();}
    @Test void publishesOnlyAfterCommit(){
        var stream=mock(DeliveryStream.class);var publisher=new CommittedDeliveryStream(stream,new ObjectMapper());TransactionSynchronizationManager.initSynchronization();
        publisher.publishDelivery(Map.of("id","delivery-1"));verifyNoInteractions(stream);
        TransactionSynchronizationManager.getSynchronizations().forEach(synchronization->synchronization.afterCommit());verify(stream).publish(any());
    }
    @Test void rollbackDoesNotPublish(){
        var stream=mock(DeliveryStream.class);var publisher=new CommittedDeliveryStream(stream,new ObjectMapper());TransactionSynchronizationManager.initSynchronization();
        publisher.publishAlert(Map.of("id","alert-1"));TransactionSynchronizationManager.getSynchronizations().forEach(synchronization->synchronization.afterCompletion(1));verifyNoInteractions(stream);
    }
    @Test void publishesImmediatelyWithoutTransaction(){var stream=mock(DeliveryStream.class);new CommittedDeliveryStream(stream,new ObjectMapper()).publishTelemetry(Map.of("id","point-1"));verify(stream).publishTelemetry(any());}
}
