import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "map",
    "feedStatus",
    "lastUpdated",
    "vehicleTotal",
    "trackingSummary",
    "trackingButton",
    "basemapButton",
    "stopCount",
    "stopHint",
    "categoryToggle",
    "stopsToggle",
    "linesToggle",
    "tramCount",
    "busCount",
    "sbahnCount",
    "obusCount",
    "railCount",
    "disruptionsPanel",
    "disruptionsList",
    "disruptionsCount"
  ]

  static values = {
    linesUrl: String,
    vehiclesUrl: String,
    stopsUrl: String,
    stopDeparturesUrl: String,
    pollInterval: { type: Number, default: 10000 }
  }

  connect() {
    this.lines = []
    this.linesLoaded = false
    this.linesLoading = false
    this.vehicleMarkers = new Map()
    this.stopMarkers = new Map()
    this.stopBoards = new Map()
    this.vehicles = []
    this.stops = []
    this.stopsLoading = false
    this.poller = null
    this.lastStopRequestKey = null
    this.stopRequestToken = 0
    this.selectedVehicleId = null
    this.trackedVehicleId = null
    this.trackingMessage = null
    this.currentBasemap = "street"
    this.currentZoom = 12
    this.routeLookup = new Map()
    this.vehicleAnimations = new Map()
    this.animationFrameId = null
    this.previousPositions = new Map()
    this.stallCounts = new Map()
    this.lineTimeline = new Map()
    this.lineTimelineMaxEntries = Math.ceil((30 * 60 * 1000) / this.pollIntervalValue)
    this.disruptionsPanelOpen = false

    this.initializeFilters()
    this.initializeMap()
    this.updateTrackingUi()
    this.refreshLines()
    this.refreshVehicles()
    if (this.stopsEnabled()) {
      this.refreshStopsForViewport()
    }
    this.poller = window.setInterval(() => this.refreshVehicles(), this.pollIntervalValue)
  }

  disconnect() {
    window.clearInterval(this.poller)

    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId)
      this.animationFrameId = null
    }

    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  toggleCategory() {
    this.initializeFilters()
    this.renderLines()
    this.renderVehicles()
    this.renderStops()
  }

  async toggleStops() {
    if (this.stopsEnabled()) {
      await this.refreshStopsForViewport()
    } else {
      this.stops = []
    }

    this.renderStops()
  }

  async toggleLines() {
    if (this.linesEnabled() && !this.linesLoaded) {
      await this.refreshLines()
      return
    }

    this.renderLines()
  }

  setBasemap(event) {
    this.currentBasemap = event.currentTarget.dataset.basemap || "street"
    this.applyBasemap()
  }

  initializeFilters() {
    this.enabledCategories = new Set(
      this.categoryToggleTargets.filter((toggle) => toggle.checked).map((toggle) => toggle.value)
    )
  }

  initializeMap() {
    if (!window.L) {
      this.updateFeedStatus("Leaflet failed to load", "error")
      return
    }

    this.map = window.L.map(this.mapTarget, {
      zoomControl: false,
      preferCanvas: true
    }).setView([48.21, 16.37], 12)
    this.currentZoom = this.map.getZoom()

    window.L.control.zoom({ position: "bottomright" }).addTo(this.map)

    this.streetLayer = window.L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19
    })

    this.aerialLayer = window.L.tileLayer("https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", {
      attribution: "Tiles &copy; Esri &mdash; Sources: Esri, Maxar, Earthstar Geographics, and the GIS User Community",
      maxZoom: 19
    })

    this.aerialLabelsLayer = window.L.tileLayer("https://server.arcgisonline.com/arcgis/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}", {
      attribution: "&copy; Esri, Garmin, HERE, OpenStreetMap contributors, and the GIS user community",
      maxZoom: 19,
      opacity: 0.92
    })

    this.applyBasemap()

    this.map.createPane("linePane")
    this.map.getPane("linePane").style.zIndex = "360"

    this.lineLayer = window.L.geoJSON([], {
      pane: "linePane",
      interactive: false,
      style: (feature) => this.lineStyle(feature)
    }).addTo(this.map)
    this.vehicleLayer = window.L.layerGroup().addTo(this.map)
    this.stopLayer = window.L.layerGroup().addTo(this.map)

    this.map.on("moveend", () => this.handleMapMoved())
    this.map.on("zoomend", () => {
      const previousProfile = this.vehicleMarkerProfile().key
      this.currentZoom = this.map.getZoom()
      if (this.vehicleMarkerProfile().key !== previousProfile) {
        this.refreshVehicleMarkers()
      }
      this.handleMapMoved()
    })
    this.map.on("dragstart", () => {
      if (this.trackedVehicleId) {
        this.releaseTracking("Camera lock released.")
      }
    })

    this.renderStopHint()
  }

  async refreshVehicles() {
    try {
      const response = await fetch(this.vehiclesUrlValue, {
        headers: { Accept: "application/json" }
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const payload = await response.json()
      this.vehicles = payload.vehicles || []
      this.renderVehicles()
      this.updateCounts(payload.counts || this.countVehicles())
      this.updateFeedStatus("Live feed online", "live")
      this.updateTimestamp(payload.fetched_at)
    } catch (error) {
      console.error("Vehicle refresh failed", error)
      this.updateFeedStatus("Live feed unavailable", "error")
    }
  }

  async refreshLines() {
    if (!this.map || this.linesLoading) {
      return
    }

    this.linesLoading = true

    try {
      const response = await fetch(this.linesUrlValue, {
        headers: { Accept: "application/json" }
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const payload = await response.json()
      this.lines = Array.isArray(payload.features) ? payload.features : []
      this.linesLoaded = payload.available !== false
      this.buildRouteLookup()
      this.renderLines()
    } catch (error) {
      console.error("Line overlay failed", error)
      this.lines = []
      this.linesLoaded = false
      this.renderLines()
    } finally {
      this.linesLoading = false
    }
  }

  renderLines() {
    if (!this.lineLayer) {
      return
    }

    this.lineLayer.clearLayers()

    if (!this.linesEnabled() || this.lines.length === 0) {
      return
    }

    const features = this.lines.filter((feature) => this.enabledCategories.has(feature?.properties?.category))
    this.lineLayer.addData(features)
  }

  renderVehicles() {
    // Snapshot current positions before updating — used by setupAnimations()
    // to animate from previous (known) position to current (known) position
    this.previousPositions = new Map()

    for (const [id, marker] of this.vehicleMarkers) {
      if (marker.vehicle) {
        this.previousPositions.set(id, { lat: marker.vehicle.lat, lng: marker.vehicle.lng })
      }
    }

    const activeIds = new Set()

    this.vehicles.forEach((vehicle) => {
      activeIds.add(vehicle.id)

      let marker = this.vehicleMarkers.get(vehicle.id)

      if (!marker) {
        marker = window.L.marker([vehicle.lat, vehicle.lng], {
          icon: this.vehicleIcon(vehicle),
          zIndexOffset: this.vehicleZIndex(vehicle),
          keyboard: false
        })
        marker.bindPopup(this.vehiclePopupHtml(vehicle), { className: "wien-live-popup" })
        marker.on("click", () => this.selectVehicle(marker.vehicle?.id || vehicle.id))
        marker.on("popupopen", () => this.selectVehicle(marker.vehicle?.id || vehicle.id))
        this.vehicleMarkers.set(vehicle.id, marker)
      }

      // Update stall counter before overwriting marker.vehicle
      this.updateStallCount(vehicle, marker.vehicle)

      marker.vehicle = vehicle
      marker.setLatLng([vehicle.lat, vehicle.lng])
      this.syncVehicleMarker(marker)

      if (this.enabledCategories.has(vehicle.category)) {
        if (!this.vehicleLayer.hasLayer(marker)) {
          marker.addTo(this.vehicleLayer)
        }
      } else if (this.vehicleLayer.hasLayer(marker)) {
        this.vehicleLayer.removeLayer(marker)
      }
    })

    this.vehicleMarkers.forEach((marker, id) => {
      if (activeIds.has(id)) {
        return
      }

      if (this.selectedVehicleId === id) {
        this.selectedVehicleId = null
      }

      if (this.trackedVehicleId === id) {
        this.trackedVehicleId = null
        this.trackingMessage = "Tracked vehicle is no longer in the live feed."
      }

      this.vehicleLayer.removeLayer(marker)
      this.vehicleMarkers.delete(id)
      this.stallCounts.delete(id)
    })

    if (this.selectedVehicleId && !activeIds.has(this.selectedVehicleId)) {
      this.selectedVehicleId = null
    }

    const trackedVehicle = this.findVehicle(this.trackedVehicleId)

    if (trackedVehicle && !this.enabledCategories.has(trackedVehicle.category)) {
      this.releaseTracking("Camera lock released because that category is hidden.")
    } else if (this.trackedVehicleId) {
      this.followTrackedVehicle()
    }

    if (this.hasVehicleTotalTarget) {
      this.vehicleTotalTarget.textContent = this.vehicles.length.toString()
    }

    this.renderLines()
    this.updateTrackingUi()
    this.setupAnimations()
    this.recordLineSnapshot()
    this.renderDisruptionsPanel()
  }

  toggleDisruptionsPanel() {
    this.disruptionsPanelOpen = !this.disruptionsPanelOpen

    if (this.hasDisruptionsPanelTarget) {
      this.disruptionsPanelTarget.dataset.open = String(this.disruptionsPanelOpen)
    }
  }

  async handleMapMoved() {
    if (this.stopsEnabled()) {
      await this.refreshStopsForViewport()
    } else {
      this.renderStops()
    }
  }

  async refreshStopsForViewport() {
    if (!this.map || !this.stopsEnabled()) {
      this.updateStopCount(0)
      this.renderStops()
      return
    }

    if (this.map.getZoom() < this.minimumStopZoom()) {
      this.stops = []
      this.updateStopCount(0)
      this.renderStops()
      return
    }

    const bounds = this.map.getBounds()
    const requestKey = [
      bounds.getSouth().toFixed(4),
      bounds.getWest().toFixed(4),
      bounds.getNorth().toFixed(4),
      bounds.getEast().toFixed(4)
    ].join(":")

    if (this.lastStopRequestKey === requestKey && this.stops.length > 0) {
      this.renderStops()
      return
    }

    this.stopsLoading = true
    this.stopRequestToken += 1
    const requestToken = this.stopRequestToken
    this.renderStopHint("Loading stop overlay...")

    try {
      const url = new URL(this.stopsUrlValue, window.location.origin)
      url.search = new URLSearchParams({
        sw_lat: bounds.getSouth().toFixed(6),
        sw_lng: bounds.getWest().toFixed(6),
        ne_lat: bounds.getNorth().toFixed(6),
        ne_lng: bounds.getEast().toFixed(6)
      }).toString()

      const response = await fetch(url, {
        headers: { Accept: "application/json" }
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const payload = await response.json()

      if (requestToken !== this.stopRequestToken) {
        return
      }

      this.stops = payload.stops || []
      this.lastStopRequestKey = requestKey
    } catch (error) {
      console.error("Stop lookup failed", error)

      if (requestToken !== this.stopRequestToken) {
        return
      }

      this.stops = []
      this.renderStopHint("Stop overlay is unavailable right now.")
    } finally {
      if (requestToken === this.stopRequestToken) {
        this.stopsLoading = false
      }
    }

    if (requestToken === this.stopRequestToken) {
      this.renderStops()
    }
  }

  renderStops() {
    if (!this.map || !this.stopsEnabled()) {
      this.clearStopLayer()
      this.updateStopCount(0)
      this.renderStopHint()
      return
    }

    if (this.map.getZoom() < this.minimumStopZoom()) {
      this.clearStopLayer()
      this.updateStopCount(0)
      this.renderStopHint(`Zoom in to level ${this.minimumStopZoom()}+ to display nearby stops.`)
      return
    }

    if (this.stopsLoading) {
      this.renderStopHint("Loading stop overlay...")
      return
    }

    const activeIds = new Set()

    this.stops.forEach((stop) => {
      if (!this.stopMatchesFilters(stop)) {
        return
      }

      activeIds.add(stop.id)

      let marker = this.stopMarkers.get(stop.id)

      if (!marker) {
        marker = window.L.circleMarker([stop.lat, stop.lng], this.stopStyle(stop))
        marker.bindPopup(this.stopPopupSkeleton(stop), { className: "wien-live-popup wien-live-popup--stop" })
        marker.on("popupopen", () => {
          if (marker.stop?.lid) {
            this.loadStopDepartures(marker, marker.stop)
          } else {
            marker.setPopupContent(this.stopPopupSkeleton(marker.stop, "Static network stop. Live departures are unavailable for this stop."))
          }
        })
        this.stopMarkers.set(stop.id, marker)
      }

      marker.stop = stop
      marker.setLatLng([stop.lat, stop.lng])
      marker.setStyle(this.stopStyle(stop))
      marker.setPopupContent(this.stopPopupSkeleton(stop))

      if (!this.stopLayer.hasLayer(marker)) {
        marker.addTo(this.stopLayer)
      }
    })

    this.stopMarkers.forEach((marker, id) => {
      if (activeIds.has(id)) {
        return
      }

      this.stopLayer.removeLayer(marker)
    })

    this.updateStopCount(activeIds.size)
    this.renderStopHint(`Showing ${activeIds.size} nearby network stops.`)
  }

  async loadStopDepartures(marker, stop) {
    if (!stop?.lid) {
      marker.setPopupContent(this.stopPopupSkeleton(stop, "Static network stop. Live departures are unavailable for this stop."))
      return
    }

    if (this.stopBoards.has(stop.lid)) {
      marker.setPopupContent(this.stopPopupHtml(stop, this.stopBoards.get(stop.lid).departures || []))
      return
    }

    marker.setPopupContent(this.stopPopupSkeleton(stop, "Loading departures..."))

    try {
      const url = new URL(this.stopDeparturesUrlValue, window.location.origin)
      url.search = new URLSearchParams({ lid: stop.lid, name: stop.name }).toString()

      const response = await fetch(url, {
        headers: { Accept: "application/json" }
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const payload = await response.json()
      this.stopBoards.set(stop.lid, payload)

      if (marker.isPopupOpen()) {
        marker.setPopupContent(this.stopPopupHtml(stop, payload.departures || []))
      }
    } catch (error) {
      console.error("Stop board lookup failed", error)

      if (marker.isPopupOpen()) {
        marker.setPopupContent(this.stopPopupSkeleton(stop, "Could not load live departures."))
      }
    }
  }

  vehicleIcon(vehicle) {
    const profile = this.vehicleMarkerProfile()
    const isTracked = vehicle.id === this.trackedVehicleId
    const isSelected = vehicle.id === this.selectedVehicleId
    const disruption = this.vehicleDisruption(vehicle)
    const classes = [
      "vehicle-marker",
      `is-${profile.key}`,
      isSelected ? "is-selected" : "",
      isTracked ? "is-tracked" : "",
      disruption.stalled ? "is-stalled" : "",
      disruption.delayMinutes >= 2 ? "is-delayed" : ""
    ].filter(Boolean).join(" ")

    return window.L.divIcon({
      className: "vehicle-marker-shell",
      iconSize: [profile.size, profile.size],
      iconAnchor: [profile.anchor, profile.anchor],
      popupAnchor: [0, profile.popupOffset],
      html: `
        <div class="${classes}" style="--marker-color:${vehicle.category_color}">
          <span class="vehicle-marker__pulse"></span>
          <span class="vehicle-marker__badge">${this.categoryIcon(vehicle.category)}</span>
          <span class="vehicle-marker__line">${this.escapeHtml(vehicle.line || vehicle.name)}</span>
          ${disruption.delayMinutes >= 2 ? `<span class="vehicle-marker__delay">+${disruption.delayMinutes}</span>` : ""}
        </div>
      `
    })
  }

  stopStyle(stop) {
    return {
      radius: this.currentZoom >= 14 ? 5.5 : 4.5,
      color: stop.category_color,
      fillColor: stop.category_color,
      fillOpacity: this.currentZoom >= 14 ? 0.46 : 0.38,
      opacity: 0.82,
      weight: 1.5
    }
  }

  lineStyle(feature) {
    const properties = feature?.properties || {}
    const highlighted = this.lineMatchesSelectedVehicle(properties)
    const baseWeight = this.currentZoom >= 14 ? 2.8 : this.currentZoom >= 12 ? 2.2 : 1.7
    const baseOpacity = this.currentBasemap === "aerial" ? 0.46 : 0.3

    return {
      color: properties.category_color || "#7dd3fc",
      opacity: highlighted ? 0.92 : baseOpacity,
      weight: highlighted ? baseWeight + 1.4 : baseWeight,
      lineCap: "round",
      lineJoin: "round"
    }
  }

  vehiclePopupHtml(vehicle) {
    const trackingActionLabel = this.trackedVehicleId === vehicle.id ? "Untrack" : "Track"
    const nextStops = (vehicle.next_stops || []).slice(0, 2)
    const hasLiveStops = nextStops.length > 0
    const progressValue = this.journeyProgressValue(vehicle.progress)
    const disruption = this.vehicleDisruption(vehicle)
    const stopItems = hasLiveStops
      ? nextStops.map((stop) => {
          const stopDelay = this.stopDelay(stop)
          const delayBadge = stopDelay >= 2
            ? ` <span class="map-popup__delay-badge">+${stopDelay} min</span>`
            : ""
          return `
            <li class="map-popup__timeline-item">
              <strong>${this.escapeHtml(stop.name)}</strong>
              <span class="map-popup__timeline-time">${this.formatMinutes(stop.minutes_away)}${delayBadge}</span>
            </li>
          `
        }).join("")
      : '<li class="is-empty">No live stop times available for this vehicle.</li>'
    const trackingState = this.trackedVehicleId === vehicle.id ? "Locked" : this.selectedVehicleId === vehicle.id ? "Selected" : "Live"
    const lineLabel = this.escapeHtml(vehicle.line || vehicle.name)
    const destinationLabel = this.escapeHtml(vehicle.direction || "Destination pending")
    const nextEta = hasLiveStops ? this.formatMinutes(nextStops[0].minutes_away) : "n/a"
    const statusLabel = this.escapeHtml(vehicle.category_label)
    const stateLabel = trackingState === "Live" ? "" : this.escapeHtml(trackingState)
    const disruptionBanner = this.disruptionBannerHtml(disruption)

    return `
      <div class="map-popup map-popup--vehicle${disruption.level !== "ok" ? ` map-popup--${disruption.level}` : ""}" style="--popup-color:${vehicle.category_color}">
        ${disruptionBanner}
        <div class="map-popup__vehicle-head">
          <span class="map-popup__route">${lineLabel}</span>
          <div class="map-popup__vehicle-copy">
            <p>${statusLabel}${stateLabel ? ` · ${stateLabel}` : ""}</p>
            <strong>${destinationLabel}</strong>
          </div>
        </div>
        <div class="map-popup__vehicle-strip">
          <span class="map-popup__state">ETA ${nextEta}</span>
          <span class="map-popup__state">${hasLiveStops ? `${nextStops.length} stops` : "No stops"}</span>
          <button
            type="button"
            class="tracking-button tracking-button--popup"
            data-action="click->live-map#toggleTracking"
            data-vehicle-id="${this.escapeHtml(vehicle.id)}"
          >
            ${trackingActionLabel}
          </button>
        </div>
        <div class="map-popup__progress">
          <div class="map-popup__progress-copy">
            <span>Progress</span>
            <strong>${progressValue}%</strong>
          </div>
          <span class="map-popup__progress-bar">
            <span style="width:${progressValue}%"></span>
          </span>
        </div>
        <div class="map-popup__section map-popup__section--compact">
          <p>Next Stops</p>
          <ul class="map-popup__timeline">${stopItems}</ul>
        </div>
      </div>
    `
  }

  stopPopupSkeleton(stop, message = "Loading departures...") {
    const categories = this.stopCategoryPills(stop)
    const lines = this.stopLinePills(stop)

    return `
      <div class="map-popup">
        <div class="map-popup__headline">
          <strong>${this.escapeHtml(stop.name)}</strong>
        </div>
        <div class="map-popup__meta">${categories}</div>
        ${lines ? `
          <div class="map-popup__section">
            <p>Lines</p>
            <div class="map-popup__pills">${lines}</div>
          </div>
        ` : ""}
        <div class="map-popup__section">
          <p>${this.escapeHtml(message)}</p>
        </div>
      </div>
    `
  }

  stopPopupHtml(stop, departures) {
    const departureItems = departures.length > 0
      ? departures.map((departure) => `
          <li>
            <span>
              <span class="map-pill map-pill--subtle" style="--pill-color:${departure.category_color}">
                ${this.escapeHtml(departure.line || departure.name)}
              </span>
              ${this.escapeHtml(departure.destination || "Destination pending")}
            </span>
            <strong>${this.formatMinutes(departure.minutes_away)}</strong>
          </li>
        `).join("")
      : '<li class="is-empty">No supported live departures found for this stop.</li>'

    return `
      <div class="map-popup">
        <div class="map-popup__headline">
          <strong>${this.escapeHtml(stop.name)}</strong>
        </div>
        <div class="map-popup__meta">${this.stopCategoryPills(stop)}</div>
        ${this.stopLinePills(stop) ? `
          <div class="map-popup__section">
            <p>Lines</p>
            <div class="map-popup__pills">${this.stopLinePills(stop)}</div>
          </div>
        ` : ""}
        <div class="map-popup__section">
          <p>Next departures</p>
          <ul>${departureItems}</ul>
        </div>
      </div>
    `
  }

  stopCategoryPills(stop) {
    return (stop.categories || []).map((category) => `
      <span class="map-pill map-pill--subtle" style="--pill-color:${category.color}">
        ${this.escapeHtml(category.label)}
      </span>
    `).join("")
  }

  stopLinePills(stop) {
    const lines = (stop.lines || []).slice(0, 10)
    const pills = lines.map((line) => `
      <span class="map-pill map-pill--subtle" style="--pill-color:${line.category_color}">
        ${this.escapeHtml(line.line)}
      </span>
    `).join("")

    if ((stop.lines || []).length <= 10) {
      return pills
    }

    return `${pills}
      <span class="map-pill map-pill--subtle" style="--pill-color:#94a3b8">
        +${this.escapeHtml((stop.lines || []).length - 10)}
      </span>
    `
  }

  updateCounts(counts) {
    this.tramCountTarget.textContent = String(counts.tram || 0)
    this.busCountTarget.textContent = String(counts.bus || 0)
    this.sbahnCountTarget.textContent = String(counts.sbahn || 0)
    this.obusCountTarget.textContent = String(counts.obus || 0)
    this.railCountTarget.textContent = String(counts.rail || 0)
  }

  updateFeedStatus(text, state) {
    if (!this.hasFeedStatusTarget) {
      return
    }

    this.feedStatusTarget.textContent = text
    this.feedStatusTarget.dataset.state = state
  }

  updateTimestamp(isoString) {
    if (!this.hasLastUpdatedTarget || !isoString) {
      return
    }

    const timestamp = new Date(isoString)

    if (Number.isNaN(timestamp.getTime())) {
      return
    }

    const formatted = new Intl.DateTimeFormat("de-AT", {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit"
    }).format(timestamp)

    this.lastUpdatedTarget.textContent = `Updated at ${formatted}`
  }

  renderStopHint(text = null) {
    if (!this.hasStopHintTarget) {
      return
    }

    if (text) {
      this.stopHintTarget.textContent = text
      return
    }

    if (!this.stopsEnabled()) {
      this.stopHintTarget.textContent = `Stops are off. Turn them on and zoom in to level ${this.minimumStopZoom()} or closer.`
      return
    }

    if (this.map && this.map.getZoom() < this.minimumStopZoom()) {
      this.stopHintTarget.textContent = `Zoom in to level ${this.minimumStopZoom()}+ to display nearby stops.`
      return
    }

    this.stopHintTarget.textContent = "Stops are on."
  }

  stopMatchesFilters(stop) {
    return (stop.categories || []).some((category) => this.enabledCategories.has(category.key))
  }

  clearStopLayer() {
    if (!this.stopLayer) {
      return
    }

    this.stopMarkers.forEach((marker) => this.stopLayer.removeLayer(marker))
  }

  stopsEnabled() {
    return this.hasStopsToggleTarget && this.stopsToggleTarget.checked
  }

  updateStopCount(count) {
    if (!this.hasStopCountTarget) {
      return
    }

    this.stopCountTarget.textContent = String(count)
  }

  toggleTracking(event) {
    const vehicleId = event?.currentTarget?.dataset?.vehicleId || this.trackedVehicleId || this.selectedVehicleId

    if (!vehicleId) {
      return
    }

    if (this.trackedVehicleId === vehicleId) {
      this.releaseTracking("Camera lock released.")
      return
    }

    this.selectedVehicleId = vehicleId
    this.trackedVehicleId = vehicleId
    this.trackingMessage = null
    this.renderVehicles()

    const marker = this.vehicleMarkers.get(vehicleId)
    marker?.openPopup()
    this.followTrackedVehicle(true)
    this.updateTrackingUi()
  }

  selectVehicle(vehicleId) {
    if (!vehicleId || this.selectedVehicleId === vehicleId) {
      return
    }

    const previousVehicleId = this.selectedVehicleId
    this.selectedVehicleId = vehicleId
    this.trackingMessage = null

    if (previousVehicleId && this.vehicleMarkers.has(previousVehicleId)) {
      this.syncVehicleMarker(this.vehicleMarkers.get(previousVehicleId))
    }

    if (this.vehicleMarkers.has(vehicleId)) {
      this.syncVehicleMarker(this.vehicleMarkers.get(vehicleId))
    }

    this.renderLines()
    this.updateTrackingUi()
  }

  releaseTracking(message = null) {
    if (!this.trackedVehicleId) {
      return
    }

    const previousTrackedId = this.trackedVehicleId
    this.trackedVehicleId = null
    this.trackingMessage = message

    if (this.vehicleMarkers.has(previousTrackedId)) {
      this.syncVehicleMarker(this.vehicleMarkers.get(previousTrackedId))
    }

    this.renderLines()
    this.updateTrackingUi()
  }

  followTrackedVehicle(animate = true) {
    if (!this.map || !this.trackedVehicleId) {
      return
    }

    const marker = this.vehicleMarkers.get(this.trackedVehicleId)

    if (!marker) {
      return
    }

    this.map.panTo(marker.getLatLng(), {
      animate,
      duration: animate ? Math.max(Math.min((this.pollIntervalValue / 1000) - 7, 2.2), 0.8) : 0,
      easeLinearity: 0.2,
      noMoveStart: true
    })
  }

  updateTrackingUi() {
    if (!this.hasTrackingSummaryTarget || !this.hasTrackingButtonTarget) {
      return
    }

    const trackedVehicle = this.findVehicle(this.trackedVehicleId)
    const selectedVehicle = this.findVehicle(this.selectedVehicleId)

    if (trackedVehicle) {
      this.trackingSummaryTarget.textContent = `${trackedVehicle.name} locked. ${this.nextStopsSummary(trackedVehicle)} Drag the map or stop tracking to release.`
      this.trackingButtonTarget.textContent = "Stop tracking"
      this.trackingButtonTarget.disabled = false
      return
    }

    if (selectedVehicle) {
      this.trackingSummaryTarget.textContent = `${selectedVehicle.name} selected toward ${selectedVehicle.direction || "its destination"}. ${this.nextStopsSummary(selectedVehicle)}`
      this.trackingButtonTarget.textContent = "Track selected vehicle"
      this.trackingButtonTarget.disabled = false
      return
    }

    this.trackingSummaryTarget.textContent = this.trackingMessage || "Select a tram, bus, or train marker to lock the camera on it."
    this.trackingButtonTarget.textContent = "Track selected vehicle"
    this.trackingButtonTarget.disabled = true
  }

  countVehicles() {
    return this.vehicles.reduce((counts, vehicle) => {
      counts[vehicle.category] = (counts[vehicle.category] || 0) + 1
      return counts
    }, { tram: 0, bus: 0, sbahn: 0, obus: 0, rail: 0 })
  }

  progressText(progress) {
    if (progress === null || progress === undefined || progress === "") {
      return "Progress unavailable"
    }

    return `${progress}% of journey complete`
  }

  journeyProgressValue(progress) {
    if (progress === null || progress === undefined || progress === "") {
      return 0
    }

    return Math.max(0, Math.min(100, Number(progress) || 0))
  }

  formatMinutes(minutes) {
    if (minutes <= 0) {
      return "now"
    }

    return `${minutes} min`
  }

  formatStopTimeHint(stop) {
    if (stop.realtime_at) {
      return "live ETA"
    }

    if (stop.scheduled_at) {
      return "scheduled"
    }

    return "upcoming"
  }

  escapeHtml(value) {
    const html = value == null ? "" : String(value)

    return html
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }

  findVehicle(vehicleId) {
    if (!vehicleId) {
      return null
    }

    return this.vehicles.find((vehicle) => vehicle.id === vehicleId) || null
  }

  applyBasemap() {
    if (!this.map) {
      return
    }

    if (this.currentBasemap === "street") {
      this.map.addLayer(this.streetLayer)
      this.map.removeLayer(this.aerialLayer)
      this.map.removeLayer(this.aerialLabelsLayer)
    } else {
      this.map.removeLayer(this.streetLayer)
      this.map.addLayer(this.aerialLayer)
      this.map.addLayer(this.aerialLabelsLayer)
    }

    this.updateBasemapButtons()
    this.renderLines()
  }

  updateBasemapButtons() {
    if (!this.hasBasemapButtonTarget) {
      return
    }

    this.basemapButtonTargets.forEach((button) => {
      button.dataset.active = String(button.dataset.basemap === this.currentBasemap)
    })
  }

  vehicleZIndex(vehicle) {
    if (vehicle.id === this.trackedVehicleId) {
      return 1200
    }

    if (vehicle.id === this.selectedVehicleId) {
      return 900
    }

    return 600
  }

  categoryIcon(category) {
    const iconClass = {
      tram: "fa-solid fa-train-tram",
      bus: "fa-solid fa-bus",
      sbahn: "fa-solid fa-train",
      obus: "fa-solid fa-bolt",
      rail: "fa-solid fa-train"
    }[category] || "fa-solid fa-location-dot"

    return `<i class="${iconClass}" aria-hidden="true"></i>`
  }

  syncVehicleMarker(marker) {
    if (!marker?.vehicle) {
      return
    }

    const visualKey = this.vehicleVisualKey(marker.vehicle)

    if (marker.visualKey !== visualKey) {
      marker.setIcon(this.vehicleIcon(marker.vehicle))
      marker.visualKey = visualKey
    }

    marker.setZIndexOffset(this.vehicleZIndex(marker.vehicle))
    marker.setPopupContent(this.vehiclePopupHtml(marker.vehicle))
  }

  vehicleVisualKey(vehicle) {
    const disruption = this.vehicleDisruption(vehicle)
    return [
      vehicle.category,
      vehicle.line,
      this.vehicleMarkerProfile().key,
      vehicle.id === this.selectedVehicleId,
      vehicle.id === this.trackedVehicleId,
      disruption.level,
      disruption.delayMinutes
    ].join(":")
  }

  nextStopsSummary(vehicle) {
    const stops = Array(vehicle.next_stops).slice(0, 2)

    if (stops.length === 0) {
      return "No live next-stop times yet."
    }

    const labels = stops.map((stop) => `${stop.name} ${this.formatMinutes(stop.minutes_away)}`)
    return `Next: ${labels.join(", ")}.`
  }

  minimumStopZoom() {
    return 12
  }

  linesEnabled() {
    return this.hasLinesToggleTarget && this.linesToggleTarget.checked
  }

  lineMatchesSelectedVehicle(properties) {
    const vehicle = this.findVehicle(this.trackedVehicleId) || this.findVehicle(this.selectedVehicleId)
    if (!vehicle) {
      return false
    }

    return properties.category === vehicle.category &&
      properties.line_token === this.normalizedLineToken(vehicle.line || vehicle.name)
  }

  normalizedLineToken(value) {
    return String(value || "").replaceAll(/\s+/g, "").toLowerCase()
  }

  vehicleMarkerProfile() {
    if (this.currentZoom <= 12) {
      return { key: "compact", size: 38, anchor: 19, popupOffset: -22 }
    }

    if (this.currentZoom <= 14) {
      return { key: "medium", size: 44, anchor: 22, popupOffset: -24 }
    }

    return { key: "detail", size: 52, anchor: 26, popupOffset: -26 }
  }

  refreshVehicleMarkers() {
    this.vehicleMarkers.forEach((marker) => this.syncVehicleMarker(marker))
    this.renderLines()
  }

  // --- Disruption detection ---

  updateStallCount(newVehicle, oldVehicle) {
    if (!oldVehicle) {
      return
    }

    const moved = Math.abs(newVehicle.lat - oldVehicle.lat) > 0.00005 ||
                  Math.abs(newVehicle.lng - oldVehicle.lng) > 0.00005

    if (moved) {
      this.stallCounts.set(newVehicle.id, 0)
    } else {
      this.stallCounts.set(newVehicle.id, (this.stallCounts.get(newVehicle.id) || 0) + 1)
    }
  }

  stopDelay(stop) {
    if (!stop.realtime_at || !stop.scheduled_at) {
      return 0
    }

    const realtime = new Date(stop.realtime_at).getTime()
    const scheduled = new Date(stop.scheduled_at).getTime()

    if (Number.isNaN(realtime) || Number.isNaN(scheduled)) {
      return 0
    }

    return Math.max(0, Math.round((realtime - scheduled) / 60000))
  }

  vehicleDisruption(vehicle) {
    const stalls = this.stallCounts.get(vehicle.id) || 0
    const stalled = stalls >= 3

    // Find max delay across next stops
    const stops = vehicle.next_stops || []
    let delayMinutes = 0

    for (const stop of stops) {
      delayMinutes = Math.max(delayMinutes, this.stopDelay(stop))
    }

    let level = "ok"

    if (stalled && delayMinutes >= 5) {
      level = "severe"
    } else if (stalled || delayMinutes >= 5) {
      level = "warning"
    } else if (delayMinutes >= 2) {
      level = "minor"
    }

    return { level, delayMinutes, stalled, stallCount: stalls }
  }

  disruptionBannerHtml(disruption) {
    if (disruption.level === "ok") {
      return ""
    }

    const parts = []

    if (disruption.delayMinutes >= 2) {
      parts.push(`Running ${disruption.delayMinutes} min late`)
    }

    if (disruption.stalled) {
      parts.push(`Stationary for ${disruption.stallCount} updates`)
    }

    return `<div class="map-popup__disruption map-popup__disruption--${disruption.level}">${parts.join(" · ")}</div>`
  }

  // --- Line timeline ---

  recordLineSnapshot() {
    const now = Date.now()
    const lineStats = new Map()

    for (const vehicle of this.vehicles) {
      const lineKey = `${vehicle.category}:${vehicle.line || vehicle.name}`

      if (!lineStats.has(lineKey)) {
        lineStats.set(lineKey, {
          line: vehicle.line || vehicle.name,
          category: vehicle.category,
          categoryLabel: vehicle.category_label,
          categoryColor: vehicle.category_color,
          vehicles: 0,
          totalDelay: 0,
          maxDelay: 0,
          stalledCount: 0
        })
      }

      const stat = lineStats.get(lineKey)
      const disruption = this.vehicleDisruption(vehicle)
      stat.vehicles += 1
      stat.totalDelay += disruption.delayMinutes
      stat.maxDelay = Math.max(stat.maxDelay, disruption.delayMinutes)

      if (disruption.stalled) {
        stat.stalledCount += 1
      }
    }

    for (const [lineKey, stat] of lineStats) {
      if (!this.lineTimeline.has(lineKey)) {
        this.lineTimeline.set(lineKey, {
          line: stat.line,
          category: stat.category,
          categoryLabel: stat.categoryLabel,
          categoryColor: stat.categoryColor,
          snapshots: []
        })
      }

      const entry = this.lineTimeline.get(lineKey)
      entry.snapshots.push({
        time: now,
        vehicles: stat.vehicles,
        avgDelay: stat.vehicles > 0 ? Math.round(stat.totalDelay / stat.vehicles) : 0,
        maxDelay: stat.maxDelay,
        stalledCount: stat.stalledCount
      })

      // Trim to rolling window
      if (entry.snapshots.length > this.lineTimelineMaxEntries) {
        entry.snapshots = entry.snapshots.slice(-this.lineTimelineMaxEntries)
      }
    }
  }

  disruptedLines() {
    const results = []

    for (const [lineKey, entry] of this.lineTimeline) {
      const snapshots = entry.snapshots
      if (snapshots.length === 0) continue

      const latest = snapshots[snapshots.length - 1]
      const hasDelay = latest.maxDelay >= 2
      const hasStalled = latest.stalledCount > 0

      if (!hasDelay && !hasStalled) continue

      results.push({
        lineKey,
        line: entry.line,
        category: entry.category,
        categoryLabel: entry.categoryLabel,
        categoryColor: entry.categoryColor,
        currentMaxDelay: latest.maxDelay,
        currentAvgDelay: latest.avgDelay,
        currentStalled: latest.stalledCount,
        currentVehicles: latest.vehicles,
        snapshots
      })
    }

    // Sort worst first
    results.sort((a, b) => {
      const scoreA = a.currentMaxDelay + (a.currentStalled * 5)
      const scoreB = b.currentMaxDelay + (b.currentStalled * 5)
      return scoreB - scoreA
    })

    return results
  }

  renderDisruptionsPanel() {
    const disrupted = this.disruptedLines()

    if (this.hasDisruptionsCountTarget) {
      this.disruptionsCountTarget.textContent = String(disrupted.length)
      this.disruptionsCountTarget.closest(".disruptions-toggle")?.classList.toggle("has-disruptions", disrupted.length > 0)
    }

    if (!this.hasDisruptionsListTarget) return

    if (disrupted.length === 0) {
      this.disruptionsListTarget.innerHTML = '<p class="disruptions__empty">All lines operating normally.</p>'
      return
    }

    this.disruptionsListTarget.innerHTML = disrupted.map((line) => {
      const sparkline = this.sparklineSvg(line.snapshots)
      const stalledLabel = line.currentStalled > 0
        ? `<span class="disruptions__stalled">${line.currentStalled} stalled</span>`
        : ""

      return `
        <div class="disruptions__line" style="--line-color:${line.categoryColor}">
          <div class="disruptions__line-head">
            <span class="disruptions__line-badge">${this.escapeHtml(line.line)}</span>
            <span class="disruptions__line-category">${this.escapeHtml(line.categoryLabel)}</span>
            <span class="disruptions__line-delay">+${line.currentMaxDelay} min</span>
            ${stalledLabel}
          </div>
          <div class="disruptions__sparkline" title="Delay trend (last 30 min)">
            ${sparkline}
          </div>
          <div class="disruptions__line-meta">
            <span>${line.currentVehicles} vehicle${line.currentVehicles !== 1 ? "s" : ""}</span>
            <span>avg +${line.currentAvgDelay} min</span>
          </div>
        </div>
      `
    }).join("")
  }

  sparklineSvg(snapshots) {
    if (snapshots.length < 2) {
      return '<svg class="sparkline" viewBox="0 0 120 28"></svg>'
    }

    const maxVal = Math.max(5, ...snapshots.map((s) => s.maxDelay))
    const width = 120
    const height = 28
    const padding = 2
    const usableW = width - padding * 2
    const usableH = height - padding * 2
    const step = usableW / (snapshots.length - 1)

    const points = snapshots.map((s, i) => {
      const x = padding + i * step
      const y = padding + usableH - (s.maxDelay / maxVal) * usableH
      return `${x.toFixed(1)},${y.toFixed(1)}`
    })

    const areaPoints = [
      `${padding},${height - padding}`,
      ...points,
      `${(padding + (snapshots.length - 1) * step).toFixed(1)},${height - padding}`
    ]

    // Determine color from latest severity
    const latest = snapshots[snapshots.length - 1]
    let stroke = "#fbbf24"
    let fill = "rgba(251,191,36,0.15)"

    if (latest.maxDelay >= 5 && latest.stalledCount > 0) {
      stroke = "#ef4444"
      fill = "rgba(239,68,68,0.15)"
    } else if (latest.maxDelay >= 5 || latest.stalledCount > 0) {
      stroke = "#f97316"
      fill = "rgba(249,115,22,0.15)"
    }

    return `
      <svg class="sparkline" viewBox="0 0 ${width} ${height}">
        <polygon points="${areaPoints.join(" ")}" fill="${fill}" />
        <polyline points="${points.join(" ")}" fill="none" stroke="${stroke}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
    `
  }

  // --- Route snapping & animation ---

  buildRouteLookup() {
    this.routeLookup = new Map()

    for (const feature of this.lines) {
      const props = feature.properties || {}
      const coords = feature.geometry?.coordinates

      if (!coords || coords.length < 2) {
        continue
      }

      const key = `${props.category}:${props.line_token}`

      if (!this.routeLookup.has(key)) {
        this.routeLookup.set(key, [])
      }

      // GeoJSON is [lng, lat] → convert to [lat, lng]
      const latLngCoords = coords.map((c) => [c[1], c[0]])
      this.routeLookup.get(key).push(latLngCoords)
    }
  }

  findVehicleRoute(vehicle) {
    if (this.routeLookup.size === 0) {
      return null
    }

    const lineToken = this.normalizedLineToken(vehicle.line || vehicle.name)
    const key = `${vehicle.category}:${lineToken}`
    const routes = this.routeLookup.get(key)

    if (!routes || routes.length === 0) {
      return null
    }

    let bestRoute = null
    let bestDistance = Infinity

    for (const coords of routes) {
      const snap = this.nearestPointOnRoute(vehicle.lat, vehicle.lng, coords)

      if (snap.distance < bestDistance) {
        bestDistance = snap.distance
        bestRoute = { coords, ...snap }
      }
    }

    // Only snap if within ~200m (roughly 0.002 degrees)
    if (bestDistance > 0.002) {
      return null
    }

    return bestRoute
  }

  nearestPointOnRoute(lat, lng, coords) {
    let bestDist = Infinity
    let bestLat = coords[0][0]
    let bestLng = coords[0][1]
    let bestSegIndex = 0
    let bestSegT = 0

    for (let i = 0; i < coords.length - 1; i++) {
      const aLat = coords[i][0]
      const aLng = coords[i][1]
      const bLat = coords[i + 1][0]
      const bLng = coords[i + 1][1]

      const dx = bLng - aLng
      const dy = bLat - aLat
      const lenSq = dx * dx + dy * dy

      let t = 0

      if (lenSq > 0) {
        t = Math.max(0, Math.min(1, ((lng - aLng) * dx + (lat - aLat) * dy) / lenSq))
      }

      const projLat = aLat + t * dy
      const projLng = aLng + t * dx
      const dist = Math.hypot(lat - projLat, lng - projLng)

      if (dist < bestDist) {
        bestDist = dist
        bestLat = projLat
        bestLng = projLng
        bestSegIndex = i
        bestSegT = t
      }
    }

    const cumLengths = this.cumulativeLengths(coords)
    const totalLength = cumLengths[cumLengths.length - 1]
    const segStart = bestSegIndex > 0 ? cumLengths[bestSegIndex - 1] : 0
    const segLen = cumLengths[bestSegIndex] - segStart
    const lengthAtPoint = segStart + segLen * bestSegT
    const fraction = totalLength > 0 ? lengthAtPoint / totalLength : 0

    return { lat: bestLat, lng: bestLng, fraction, distance: bestDist }
  }

  cumulativeLengths(coords) {
    const result = []
    let total = 0

    for (let i = 0; i < coords.length - 1; i++) {
      total += Math.hypot(
        coords[i + 1][0] - coords[i][0],
        coords[i + 1][1] - coords[i][1]
      )
      result.push(total)
    }

    return result
  }

  interpolateAlongRoute(coords, fraction) {
    if (fraction <= 0) {
      return { lat: coords[0][0], lng: coords[0][1] }
    }

    if (fraction >= 1) {
      return { lat: coords[coords.length - 1][0], lng: coords[coords.length - 1][1] }
    }

    const cumLengths = this.cumulativeLengths(coords)
    const totalLength = cumLengths[cumLengths.length - 1]
    const targetLength = fraction * totalLength

    for (let i = 0; i < cumLengths.length; i++) {
      const segStart = i > 0 ? cumLengths[i - 1] : 0

      if (targetLength <= cumLengths[i]) {
        const segLen = cumLengths[i] - segStart
        const t = segLen > 0 ? (targetLength - segStart) / segLen : 0

        return {
          lat: coords[i][0] + t * (coords[i + 1][0] - coords[i][0]),
          lng: coords[i][1] + t * (coords[i + 1][1] - coords[i][1])
        }
      }
    }

    return { lat: coords[coords.length - 1][0], lng: coords[coords.length - 1][1] }
  }

  setupAnimations() {
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId)
      this.animationFrameId = null
    }

    this.vehicleAnimations.clear()
    const now = performance.now()

    for (const [id, marker] of this.vehicleMarkers) {
      const vehicle = marker.vehicle

      if (!vehicle || !this.enabledCategories.has(vehicle.category)) {
        continue
      }

      const routeMatch = this.findVehicleRoute(vehicle)

      if (!routeMatch) {
        continue
      }

      const prev = this.previousPositions.get(id)

      if (!prev) {
        // First appearance — snap to route, no animation
        marker.setLatLng([routeMatch.lat, routeMatch.lng])
        continue
      }

      // Both points snapped to the SAME route shape
      const prevSnap = this.nearestPointOnRoute(prev.lat, prev.lng, routeMatch.coords)
      const currFraction = routeMatch.fraction
      const prevFraction = prevSnap.fraction

      // Didn't move? Snap and stay still
      if (Math.abs(currFraction - prevFraction) < 0.0001) {
        marker.setLatLng([routeMatch.lat, routeMatch.lng])
        continue
      }

      // Place marker at previous position, animate to current
      marker.setLatLng([prevSnap.lat, prevSnap.lng])

      this.vehicleAnimations.set(id, {
        coords: routeMatch.coords,
        startFraction: prevFraction,
        endFraction: currFraction,
        startTime: now,
        duration: this.pollIntervalValue * 0.8
      })
    }

    if (this.vehicleAnimations.size > 0) {
      this.animationFrameId = requestAnimationFrame((t) => this.animationTick(t))
    }
  }

  animationTick(timestamp) {
    let hasActive = false

    for (const [id, anim] of this.vehicleAnimations) {
      const marker = this.vehicleMarkers.get(id)

      if (!marker) {
        continue
      }

      const elapsed = timestamp - anim.startTime
      const progress = Math.min(elapsed / anim.duration, 1)

      const fraction = anim.startFraction + (anim.endFraction - anim.startFraction) * progress
      const pos = this.interpolateAlongRoute(anim.coords, fraction)
      marker.setLatLng([pos.lat, pos.lng])

      if (progress < 1) {
        hasActive = true
      }
    }

    // Keep tracked vehicle centered during animation
    if (this.trackedVehicleId && this.vehicleAnimations.has(this.trackedVehicleId)) {
      const marker = this.vehicleMarkers.get(this.trackedVehicleId)

      if (marker && this.map) {
        this.map.panTo(marker.getLatLng(), { animate: false, noMoveStart: true })
      }
    }

    if (hasActive) {
      this.animationFrameId = requestAnimationFrame((t) => this.animationTick(t))
    } else {
      this.animationFrameId = null
    }
  }
}
