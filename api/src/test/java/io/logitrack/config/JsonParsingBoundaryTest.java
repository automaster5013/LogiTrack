package io.logitrack.config;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
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
}
