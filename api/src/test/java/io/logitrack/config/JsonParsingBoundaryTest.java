package io.logitrack.config;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.order.DispatchOrderRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.json.JsonTest;

import static org.junit.jupiter.api.Assertions.*;

@JsonTest
class JsonParsingBoundaryTest {
    @Autowired ObjectMapper mapper;

    @Test void rejectsDuplicateObjectKeys() {
        assertThrows(JsonProcessingException.class,()->mapper.readTree("{\"role\":\"VIEWER\",\"role\":\"ADMIN\"}"));
    }

    @Test void acceptsDistinctObjectKeys() {
        assertDoesNotThrow(()->mapper.readTree("{\"role\":\"VIEWER\",\"subject\":\"operator-a\"}"));
    }

    @Test void rejectsUnknownRequestProperties() {
        assertThrows(JsonProcessingException.class, () -> mapper.readValue(
                "{\"vehicleId\":\"TRUCK-01\",\"role\":\"ADMIN\"}", DispatchOrderRequest.class));
    }

    @Test void acceptsDeclaredRequestProperties() {
        DispatchOrderRequest request = assertDoesNotThrow(() -> mapper.readValue(
                "{\"vehicleId\":\"TRUCK-01\"}", DispatchOrderRequest.class));
        assertEquals("TRUCK-01", request.vehicleId());
    }
}
