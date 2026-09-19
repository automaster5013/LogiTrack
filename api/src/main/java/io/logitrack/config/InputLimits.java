package io.logitrack.config;

public final class InputLimits {
    private InputLimits() {}
    public static void required(String value,String field,int max){
        if(value==null||value.isBlank())throw new IllegalArgumentException(field+" is required");
        if(value.length()>max)throw new IllegalArgumentException(field+" must be at most "+max+" characters");
    }
}
