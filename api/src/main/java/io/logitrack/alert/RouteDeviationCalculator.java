package io.logitrack.alert;

import com.fasterxml.jackson.databind.JsonNode;

public final class RouteDeviationCalculator {
    private static final double EARTH_RADIUS=6_371_000d;
    private RouteDeviationCalculator() {}
    public static double distanceMeters(double lat,double lon,JsonNode geometry) {
        var coordinates=geometry.path("coordinates");
        if(!coordinates.isArray()||coordinates.size()<2) return Double.POSITIVE_INFINITY;
        var cos=Math.cos(Math.toRadians(lat)); var minimum=Double.POSITIVE_INFINITY;
        for(int i=0;i<coordinates.size()-1;i++){
            var a=coordinates.get(i); var b=coordinates.get(i+1);
            var ax=Math.toRadians(a.get(0).asDouble()-lon)*cos*EARTH_RADIUS;
            var ay=Math.toRadians(a.get(1).asDouble()-lat)*EARTH_RADIUS;
            var bx=Math.toRadians(b.get(0).asDouble()-lon)*cos*EARTH_RADIUS;
            var by=Math.toRadians(b.get(1).asDouble()-lat)*EARTH_RADIUS;
            var dx=bx-ax; var dy=by-ay; var length=dx*dx+dy*dy;
            var t=length==0?0:Math.max(0,Math.min(1,-(ax*dx+ay*dy)/length));
            minimum=Math.min(minimum,Math.hypot(ax+t*dx,ay+t*dy));
        }
        return minimum;
    }
}

