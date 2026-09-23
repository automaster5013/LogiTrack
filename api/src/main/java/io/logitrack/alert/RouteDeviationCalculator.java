package io.logitrack.alert;

import com.fasterxml.jackson.databind.JsonNode;

public final class RouteDeviationCalculator {
    private static final double EARTH_RADIUS=6_371_000d;
    private RouteDeviationCalculator() {}
    public static double distanceMeters(double lat,double lon,JsonNode geometry) {
        if(!Double.isFinite(lat)||!Double.isFinite(lon)||lat < -90||lat > 90||lon < -180||lon > 180||geometry==null) {
            return Double.POSITIVE_INFINITY;
        }
        var coordinates=geometry.path("coordinates");
        if(!coordinates.isArray()||coordinates.size()<2) return Double.POSITIVE_INFINITY;
        var cos=Math.cos(Math.toRadians(lat)); var minimum=Double.POSITIVE_INFINITY;
        for(int i=0;i<coordinates.size()-1;i++){
            var a=coordinates.get(i); var b=coordinates.get(i+1);
            if(!validCoordinate(a)||!validCoordinate(b)) return Double.POSITIVE_INFINITY;
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

    private static boolean validCoordinate(JsonNode coordinate) {
        if(coordinate==null||!coordinate.isArray()||coordinate.size()<2
                ||!coordinate.get(0).isNumber()||!coordinate.get(1).isNumber()) return false;
        var lon=coordinate.get(0).asDouble(); var lat=coordinate.get(1).asDouble();
        return Double.isFinite(lat)&&Double.isFinite(lon)&&lat>=-90&&lat<=90&&lon>=-180&&lon<=180;
    }
}

