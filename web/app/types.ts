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
};

export type WarehouseStock = { id:string; warehouseId:string; sku:string; onHand:number; reserved:number; available:number; updatedAt:string };
export type WarehouseTask = { id:string; taskType:"INBOUND"|"OUTBOUND"; status:"RECEIVED"|"PICKED"|"DISPATCHED"; referenceNumber:string; warehouseId:string; sku:string; quantity:number; createdAt:string };
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
  status: "PENDING" | "REPLAYED";
  failedAt: string;
  replayedAt?: string;
  replayedBy?: string;
};

export type ReplayAudit = { id:string; deadLetterEventId:string; action:"REPLAY"; actor:string; occurredAt:string };
