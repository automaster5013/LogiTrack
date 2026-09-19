package io.logitrack.alert;

public record UpsertAlertPolicyRequest(String vehicleId,double deviationOpenMeters,double deviationCloseMeters,
    double criticalDeviationMeters,long delayOpenSeconds,long delayCloseSeconds,long criticalDelaySeconds) {}
