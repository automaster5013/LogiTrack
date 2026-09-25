import "./styles.css";
import "./track.css";
import "maplibre-gl/dist/maplibre-gl.css";
import RuntimeVersionGuard from "./components/RuntimeVersionGuard";
export const metadata = { title: "LogiTrack Control Tower", description: "Real-time logistics operations" };
export const dynamic = "force-dynamic";
export default function Layout({children}:{children:React.ReactNode}) { return <html lang="ko"><body><RuntimeVersionGuard/>{children}</body></html>; }
