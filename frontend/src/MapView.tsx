import { useEffect } from "react"
import L from "leaflet"
import { Circle, MapContainer, Marker, Polyline, TileLayer, useMap } from "react-leaflet"
import "leaflet/dist/leaflet.css"

type Coordinate = [number, number]

type MapViewProps = {
  parked?: Coordinate | null
  current?: Coordinate | null
  accuracy?: number | null
  compact?: boolean
}

function MapCamera({ parked, current }: Pick<MapViewProps, "parked" | "current">) {
  const map = useMap()

  useEffect(() => {
    if (parked && current) {
      map.fitBounds(L.latLngBounds(parked, current).pad(0.35), { maxZoom: 19 })
    } else if (parked) {
      map.setView(parked, 18)
    } else if (current) {
      map.setView(current, 17)
    } else {
      map.setView([20, 0], 2)
    }
  }, [current, map, parked])

  useEffect(() => {
    const timer = window.setTimeout(() => map.invalidateSize(), 120)
    return () => window.clearTimeout(timer)
  }, [map])

  return null
}

function makeMarker(label: string, className: string) {
  return L.divIcon({
    className: "map-marker-shell",
    html: `<span class="map-marker ${className}">${label}</span>`,
    iconSize: [34, 34],
    iconAnchor: [17, 17],
  })
}

const parkedIcon = makeMarker("P", "map-marker-parked")
const currentIcon = makeMarker("", "map-marker-current")

export default function MapView({ parked = null, current = null, accuracy = null, compact = false }: MapViewProps) {
  const center = parked ?? current ?? [20, 0]

  return (
    <div className={`map-frame${compact ? " map-frame-compact" : ""}`}>
      <MapContainer center={center} zoom={parked || current ? 17 : 2} scrollWheelZoom={false} zoomControl={!compact}>
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
          maxZoom={19}
        />
        <MapCamera parked={parked} current={current} />
        {parked && <Marker position={parked} icon={parkedIcon} />}
        {current && (
          <>
            <Marker position={current} icon={currentIcon} />
            {accuracy !== null && <Circle center={current} radius={accuracy} pathOptions={{ color: "#2e7773", weight: 1, fillOpacity: 0.1 }} />}
          </>
        )}
        {parked && current && <Polyline positions={[current, parked]} pathOptions={{ color: "#4568a2", weight: 3, dashArray: "6 8" }} />}
      </MapContainer>
    </div>
  )
}
