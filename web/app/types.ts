export type Delivery = {
  id: string;
  orderId?: string;
  orderNumber: string;
  vehicleId: string;
  status: "CREATED" | "IN_TRANSIT" | "DELAYED" | "DELIVERED";
  originName: string;
  originLat: number;
  originLon: number;
  destinationName: string;
  destinationLat: number;
  destinationLon: number;
  currentLat: number;
  currentLon: number;
  progress: number;
  eta?: string;
  lastTelemetryAt?: string;
};

export type CustomerOrder = {
  id: string;
  orderNumber: string;
  status: "READY" | "DISPATCHED" | "FULFILLED";
  originName: string;
  originLat: number;
  originLon: number;
  destinationName: string;
  destinationLat: number;
  destinationLon: number;
  deliveryId?: string;
  vehicleId?: string;
  deliveryStatus?: Delivery["status"];
  createdAt: string;
  updatedAt: string;
};

export type RouteSnapshot = {
  id: string;
  deliveryId: string;
  provider: string;
  algorithmVersion: string;
  geometry: { type: "LineString"; coordinates: [number, number][] };
  geometryHash: string;
  distanceMeters: number;
  durationSeconds: number;
  plannedEta: string;
  generatedAt: string;
};

export type TelemetryPoint = {
  eventId: string;
  deliveryId: string;
  vehicleId: string;
  latitude: number;
  longitude: number;
  progress: number;
  occurredAt: string;
};

export type DeliveryAlert = {
  id: string;
  deliveryId: string;
  alertType: "DELAY" | "ROUTE_DEVIATION";
  severity: "WARNING" | "CRITICAL";
  status: "ACTIVE" | "RESOLVED";
  message: string;
  observedValue: number;
  thresholdValue: number;
  occurrenceCount: number;
  firstObservedAt: string;
  lastObservedAt: string;
  resolvedAt?: string;
  acknowledgedAt?: string;
  acknowledgedBy?: string;
};

export type AlertPolicy = {
  id: string;
  vehicleId: string;
  deviationOpenMeters: number;
  deviationCloseMeters: number;
  criticalDeviationMeters: number;
  delayOpenSeconds: number;
  delayCloseSeconds: number;
  criticalDelaySeconds: number;
  updatedAt: string;
  updatedBy: string;
};

export type AlertPolicyAudit = Omit<AlertPolicy,"updatedAt"|"updatedBy"> & {
  policyId: string;
  action: "UPSERT" | "RESET" | "RESTORE";
  actor: string;
  occurredAt: string;
};

export type WarehouseStock = { id:string; warehouseId:string; sku:string; onHand:number; reserved:number; available:number; updatedAt:string };
export type WarehouseTask = { id:string; taskType:"INBOUND"|"OUTBOUND"; status:"RECEIVED"|"PICKED"|"DISPATCHED"; referenceNumber:string; warehouseId:string; sku:string; quantity:number; createdAt:string; updatedAt:string };
export type LedgerEntry = { id:string; taskId:string; warehouseId:string; sku:string; transactionType:"RECEIPT"|"PICK"|"DISPATCH"; onHandDelta:number; reservedDelta:number; onHandAfter:number; reservedAfter:number; occurredAt:string };

export type DailyDeliveryKpi = {
  metricDate: string;
  totalDeliveries: number;
  activeDeliveries: number;
  deliveredDeliveries: number;
  delayedDeliveries: number;
  averageProgressPercent: number;
  averageCycleMinutes: number;
  onTimeRatePercent: number;
  projectedAt: string;
};

export type DeadLetterEvent = {
  id: string;
  originalTopic: string;
  messageKey?: string;
  payload: string;
  traceId?: string;
  exceptionMessage?: string;
  dlqPartition: number;
  dlqOffset: number;
  status: "PENDING" | "REPLAYED" | "DISCARDED";
  failedAt: string;
  replayedAt?: string;
  replayedBy?: string;
  discardedAt?: string;
  discardedBy?: string;
  discardReason?: string;
};

export type ReplayAudit = { id:string; deadLetterEventId:string; action:"REPLAY"|"DISCARD"; actor:string; reason?:string; occurredAt:string };
export type DeadLetterPage = { items:DeadLetterEvent[]; page:number; size:number; totalElements:number; hasMore:boolean };
export type DiscardPlan = { id:string; actor:string; reason:string; eventIds:string[]; status:"PREPARED"|"EXECUTED"|"PARTIAL"|"EXPIRED"; createdAt:string; expiresAt:string; executedAt?:string; succeededCount:number; failedCount:number };
export type OutboxFailure = { id:string; aggregateType:string; aggregateId:string; eventType:string; topic:string; attempts:number; lastError?:string; createdAt:string; status:"FAILED"|"PENDING" };
export type OutboxRetryAudit = { id:string; outboxEventId:string; actor:string; occurredAt:string };
