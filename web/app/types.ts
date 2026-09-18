export type Delivery = {
  id: string;
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

export type WarehouseStock = { id:string; warehouseId:string; sku:string; onHand:number; reserved:number; available:number; updatedAt:string };
export type WarehouseTask = { id:string; taskType:"INBOUND"|"OUTBOUND"; status:"RECEIVED"|"PICKED"|"DISPATCHED"; referenceNumber:string; warehouseId:string; sku:string; quantity:number; createdAt:string };
export type LedgerEntry = { id:string; taskId:string; warehouseId:string; sku:string; transactionType:"RECEIPT"|"PICK"|"DISPATCH"; onHandDelta:number; reservedDelta:number; onHandAfter:number; reservedAfter:number; occurredAt:string };
