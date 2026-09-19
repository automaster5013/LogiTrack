package io.logitrack.config;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class InputLimitsTest {
    @Test void acceptsBoundaryAndRejectsBlankOrOversized(){
        assertDoesNotThrow(()->InputLimits.required("x".repeat(80),"field",80));
        assertThrows(IllegalArgumentException.class,()->InputLimits.required(" ","field",80));
        assertThrows(IllegalArgumentException.class,()->InputLimits.required("x".repeat(81),"field",80));
    }
}
