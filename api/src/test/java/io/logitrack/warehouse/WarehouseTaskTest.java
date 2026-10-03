package io.logitrack.warehouse;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class WarehouseTaskTest {
    private final WarehouseCommand command=new WarehouseCommand("OUT-1","WH-1","SKU-1",4);

    @Test void legacyDispatchedTaskCanClaimExactlyOneRequestKey(){
        var task=WarehouseTask.outbound(command,"pick-key");
        task.dispatch();

        task.bindDispatchRequestKey("dispatch-key");

        assertEquals("dispatch-key",task.getDispatchRequestKey());
        assertThrows(IllegalStateException.class,()->task.bindDispatchRequestKey("dispatch-key"));
        assertThrows(IllegalStateException.class,()->task.bindDispatchRequestKey("other-key"));
    }

    @Test void undispatchedTaskCannotClaimARequestKey(){
        var task=WarehouseTask.outbound(command,"pick-key");

        assertThrows(IllegalStateException.class,()->task.bindDispatchRequestKey("dispatch-key"));
    }
}
