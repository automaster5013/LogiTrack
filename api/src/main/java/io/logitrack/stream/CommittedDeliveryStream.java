package io.logitrack.stream;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

@Component
public class CommittedDeliveryStream {
    private final DeliveryStream stream;
    private final ObjectMapper mapper;

    public CommittedDeliveryStream(DeliveryStream stream,ObjectMapper mapper){this.stream=stream;this.mapper=mapper;}

    public void publishDelivery(Object value){var payload=snapshot(value);afterCommit(()->stream.publish(payload));}
    public void publishAlert(Object value){var payload=snapshot(value);afterCommit(()->stream.publishAlert(payload));}
    public void publishTelemetry(Object value){var payload=snapshot(value);afterCommit(()->stream.publishTelemetry(payload));}

    private Object snapshot(Object value){return mapper.valueToTree(value);}
    private void afterCommit(Runnable action){
        if(!TransactionSynchronizationManager.isSynchronizationActive()){action.run();return;}
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization(){@Override public void afterCommit(){action.run();}});
    }
}
