package io.logitrack.report;

import java.time.Instant;
import java.time.LocalDate;

public record DailyDeliveryKpi(
    LocalDate metricDate,
    long totalDeliveries,
    long activeDeliveries,
    long deliveredDeliveries,
    long delayedDeliveries,
    double averageProgressPercent,
    double averageCycleMinutes,
    double onTimeRatePercent,
    Instant projectedAt
) {}

