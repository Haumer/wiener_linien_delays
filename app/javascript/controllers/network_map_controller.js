import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["map"]
  static values = {
    linesUrl: String,
    stopsUrl: String,
    lineHealthUrl: String
  }

  connect() {
    this.lineHealth = {}
    this.initMap()
    this.loadData()
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  initMap() {
    this.map = window.L.map(this.mapTarget, {
      zoomControl: true,
      preferCanvas: true,
      zoomSnap: 0.5
    }).setView([48.21, 16.37], 12)

    // Clean white background — no street tiles
    window.L.tileLayer("https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_nolabels/{z}/{x}/{y}{r}.png", {
      attribution: '&copy; <a href="https://carto.com/">CARTO</a>',
      maxZoom: 18
    }).addTo(this.map)
  }

  async loadData() {
    const [lines, health] = await Promise.all([
      this.fetchJson(this.linesUrlValue),
      this.fetchJson(this.lineHealthUrlValue)
    ])

    // Index line health by line name
    if (health?.lines) {
      for (const line of health.lines) {
        this.lineHealth[line.line] = line
      }
    }

    // Render lines
    if (lines?.features) {
      this.renderLines(lines.features)
    }

    // Load stops for current viewport
    this.loadStops()
    this.map.on("moveend", () => this.loadStops())
  }

  renderLines(features) {
    // Group features by line to draw each once (pick longest shape per line)
    const byLine = new Map()

    for (const feature of features) {
      const key = `${feature.properties.category}:${feature.properties.line}`
      const coords = feature.geometry?.coordinates || []

      if (!byLine.has(key) || coords.length > byLine.get(key).geometry.coordinates.length) {
        byLine.set(key, feature)
      }
    }

    for (const [key, feature] of byLine) {
      const props = feature.properties
      const health = this.lineHealth[props.line]
      const isDelayed = health && health.status !== "ok"

      const line = window.L.geoJSON(feature, {
        style: {
          color: props.category_color || "#94a3b8",
          weight: isDelayed ? 5 : 3.5,
          opacity: isDelayed ? 0.95 : 0.7,
          lineCap: "round",
          lineJoin: "round"
        },
        interactive: true
      }).addTo(this.map)

      // Popup with line info
      const delayInfo = health
        ? `<br><strong>Status:</strong> ${this.statusLabel(health.status)}<br><strong>Avg delay:</strong> ${(health.avg_delay_seconds / 60).toFixed(1)} min<br><strong>Vehicles:</strong> ${health.vehicle_count}`
        : ""

      line.bindPopup(`
        <div style="font-family:system-ui;font-size:13px">
          <strong style="font-size:15px">${this.escapeHtml(props.name || props.line)}</strong>
          <br><span style="color:#64748b">${this.escapeHtml(props.category_label)}</span>
          ${delayInfo}
          <br><a href="/delays/${encodeURIComponent(props.line)}" style="color:#2563eb;font-weight:600">View delay details →</a>
        </div>
      `)
    }
  }

  async loadStops() {
    if (this.map.getZoom() < 13) return

    const bounds = this.map.getBounds()
    const url = new URL(this.stopsUrlValue, window.location.origin)
    url.search = new URLSearchParams({
      sw_lat: bounds.getSouth().toFixed(6),
      sw_lng: bounds.getWest().toFixed(6),
      ne_lat: bounds.getNorth().toFixed(6),
      ne_lng: bounds.getEast().toFixed(6)
    }).toString()

    const data = await this.fetchJson(url)
    if (!data?.stops) return

    // Clear old stop markers
    if (this.stopLayer) {
      this.map.removeLayer(this.stopLayer)
    }

    this.stopLayer = window.L.layerGroup().addTo(this.map)

    for (const stop of data.stops) {
      const lineCount = (stop.lines || []).length
      const isInterchange = lineCount >= 3
      const radius = isInterchange ? 6.5 : 4
      const color = isInterchange ? "#0f172a" : (stop.category_color || "#64748b")

      const marker = window.L.circleMarker([stop.lat, stop.lng], {
        radius: radius,
        color: "#fff",
        weight: isInterchange ? 2.5 : 1.5,
        fillColor: color,
        fillOpacity: 0.9,
        opacity: 1
      }).addTo(this.stopLayer)

      // Popup
      const linesPills = (stop.lines || []).slice(0, 12).map(l =>
        `<span style="display:inline-block;padding:2px 6px;border-radius:4px;background:${l.category_color};color:#fff;font-size:11px;font-weight:700;margin:1px">${this.escapeHtml(l.line)}</span>`
      ).join(" ")

      marker.bindPopup(`
        <div style="font-family:system-ui;font-size:13px;max-width:200px">
          <strong style="font-size:14px">${this.escapeHtml(stop.name)}</strong>
          <div style="margin-top:6px">${linesPills}</div>
        </div>
      `)

      // Show name label for interchanges at higher zoom
      if (isInterchange && this.map.getZoom() >= 14) {
        window.L.marker([stop.lat, stop.lng], {
          icon: window.L.divIcon({
            className: "network-stop-label",
            html: `<span>${this.escapeHtml(stop.name)}</span>`,
            iconSize: [0, 0],
            iconAnchor: [0, -10]
          }),
          interactive: false
        }).addTo(this.stopLayer)
      }
    }
  }

  statusLabel(status) {
    return {
      ok: "✓ On time",
      minor_delay: "⚠ Minor delay",
      major_delay: "⚠ Major delay",
      disrupted: "✕ Disrupted"
    }[status] || status
  }

  escapeHtml(value) {
    const html = value == null ? "" : String(value)
    return html
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
  }

  async fetchJson(url) {
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return null
      return await response.json()
    } catch {
      return null
    }
  }
}
