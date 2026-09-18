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

