package io.logitrack.replay;

import java.util.List;
import java.util.UUID;

public record CreateDiscardPlanRequest(List<UUID> eventIds,String reason) {}
