package io.logitrack.config;

import org.junit.jupiter.api.Test;
import org.springframework.util.unit.DataSize;

import static org.junit.jupiter.api.Assertions.*;

class HttpContainerBoundaryValidatorTest {
    @Test void acceptsBoundedContainerLimits(){
        assertDoesNotThrow(()->validator(DataSize.ofKilobytes(8),DataSize.ofKilobytes(8),DataSize.ofMegabytes(1),DataSize.ofMegabytes(1)).validate());
    }

    @Test void rejectsUnboundedRequestHeaders(){
        assertThrows(IllegalStateException.class,()->validator(DataSize.ofKilobytes(17),DataSize.ofKilobytes(8),DataSize.ofMegabytes(1),DataSize.ofMegabytes(1)).validate());
    }

    @Test void rejectsUnboundedResponseHeaders(){
        assertThrows(IllegalStateException.class,()->validator(DataSize.ofKilobytes(8),DataSize.ofKilobytes(33),DataSize.ofMegabytes(1),DataSize.ofMegabytes(1)).validate());
    }

    @Test void rejectsDisabledOrOversizedBodyHandling(){
        assertThrows(IllegalStateException.class,()->validator(DataSize.ofKilobytes(8),DataSize.ofKilobytes(8),DataSize.ofBytes(0),DataSize.ofMegabytes(1)).validate());
        assertThrows(IllegalStateException.class,()->validator(DataSize.ofKilobytes(8),DataSize.ofKilobytes(8),DataSize.ofMegabytes(1),DataSize.ofMegabytes(11)).validate());
    }

    private static HttpContainerBoundaryValidator validator(DataSize request,DataSize response,DataSize form,DataSize swallow){
        return new HttpContainerBoundaryValidator(request,response,form,swallow);
    }
}
