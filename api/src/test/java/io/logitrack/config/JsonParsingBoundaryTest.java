package io.logitrack.config;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.order.DispatchOrderRequest;
import io.logitrack.warehouse.WarehouseCommand;
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

    @Test void rejectsTrailingJsonValues() {
        assertThrows(JsonProcessingException.class, () -> mapper.readValue(
                "{\"vehicleId\":\"TRUCK-01\"} {\"vehicleId\":\"TRUCK-02\"}",
                DispatchOrderRequest.class));
    }

    @Test void rejectsStringCoercionForNumericFields() {
        assertThrows(JsonProcessingException.class, () -> mapper.readValue(
                "{\"referenceNumber\":\"REF-01\",\"warehouseId\":\"WH-01\","
                        + "\"sku\":\"SKU-01\",\"quantity\":\"10\"}",
                WarehouseCommand.class));
    }

    @Test void acceptsNumericFieldsWithTheirDeclaredType() {
        WarehouseCommand command = assertDoesNotThrow(() -> mapper.readValue(
                "{\"referenceNumber\":\"REF-01\",\"warehouseId\":\"WH-01\","
                        + "\"sku\":\"SKU-01\",\"quantity\":10}",
                WarehouseCommand.class));
        assertEquals(10, command.quantity());
    }

    @Test void rejectsNullForPrimitiveFields() {
        assertThrows(JsonProcessingException.class, () -> mapper.readValue(
                "{\"referenceNumber\":\"REF-01\",\"warehouseId\":\"WH-01\","
                        + "\"sku\":\"SKU-01\",\"quantity\":null}",
                WarehouseCommand.class));
    }
}
