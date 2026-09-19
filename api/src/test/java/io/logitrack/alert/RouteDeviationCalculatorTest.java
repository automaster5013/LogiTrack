package io.logitrack.alert;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class RouteDeviationCalculatorTest {
    private final ObjectMapper mapper=new ObjectMapper();
    @Test void pointOnRouteHasNearZeroDeviation() throws Exception {
        var route=mapper.readTree("{\"coordinates\":[[126.9,37.5],[127.0,37.5]]}");
        assertTrue(RouteDeviationCalculator.distanceMeters(37.5,126.95,route)<1);
    }
    @Test void detectsKilometerScaleDeviation() throws Exception {
        var route=mapper.readTree("{\"coordinates\":[[126.9,37.5],[127.0,37.5]]}");
        var distance=RouteDeviationCalculator.distanceMeters(37.51,126.95,route);
        assertTrue(distance>1_000&&distance<1_200);
    }
    @Test void invalidGeometryIsNotSilentlyAccepted() throws Exception {
        assertEquals(Double.POSITIVE_INFINITY,RouteDeviationCalculator.distanceMeters(0,0,mapper.readTree("{}")));
    }

    @Test void supportsDegenerateSegmentsAndClosestEndpoints() throws Exception {
        var repeated=mapper.readTree("{\"coordinates\":[[126.9,37.5],[126.9,37.5]]}");
        assertTrue(RouteDeviationCalculator.distanceMeters(37.5,126.9,repeated)<1);

        var route=mapper.readTree("{\"coordinates\":[[126.9,37.5],[127.0,37.5]]}");
        assertTrue(RouteDeviationCalculator.distanceMeters(37.5,126.8,route)>8_000);
        assertTrue(RouteDeviationCalculator.distanceMeters(37.5,127.1,route)>8_000);
    }
}
