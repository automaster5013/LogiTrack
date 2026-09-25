package io.logitrack.config;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.order.DispatchOrderRequest;
import io.logitrack.warehouse.WarehouseCommand;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.json.JsonTest;
import org.springframework.context.annotation.Import;

import static org.junit.jupiter.api.Assertions.*;

@JsonTest
@Import(JsonParsingConfig.class)
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

    @Test void rejectsExcessivelyNestedJson() {
        String nested = "[".repeat(101) + "0" + "]".repeat(101);
        assertThrows(JsonProcessingException.class, () -> mapper.readTree(nested));
    }

    @Test void acceptsJsonAtConfiguredNestingDepth() {
        String nested = "[".repeat(100) + "0" + "]".repeat(100);
        assertDoesNotThrow(() -> mapper.readTree(nested));
        assertEquals(100, mapper.getFactory().streamReadConstraints().getMaxNestingDepth());
    }

    @Test void rejectsUnsafeNestingConfiguration() {
        assertThrows(IllegalArgumentException.class, () -> new JsonParsingConfig(0));
        assertThrows(IllegalArgumentException.class, () -> new JsonParsingConfig(201));
        assertDoesNotThrow(() -> new JsonParsingConfig(1));
        assertDoesNotThrow(() -> new JsonParsingConfig(200));
    }
}
