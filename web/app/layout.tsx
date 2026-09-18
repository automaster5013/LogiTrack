import "./styles.css";
import "maplibre-gl/dist/maplibre-gl.css";
export const metadata = { title: "LogiTrack Control Tower", description: "Real-time logistics operations" };
export default function Layout({children}:{children:React.ReactNode}) { return <html lang="ko"><body>{children}</body></html>; }
