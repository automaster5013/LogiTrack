package io.logitrack.replay;

import java.util.List;
import java.util.UUID;

public record CreateReplayPlanRequest(List<UUID> eventIds) {}

