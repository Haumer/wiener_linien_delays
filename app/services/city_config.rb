class CityConfig
  CITIES = {
    "wien" => {
      name: "Wien",
      label: "Vienna",
      rect: { llCrd: { x: 16_180_000, y: 48_110_000 }, urCrd: { x: 16_580_000, y: 48_330_000 } },
      center: [48.21, 16.37]
    },
    "graz" => {
      name: "Graz",
      label: "Graz",
      rect: { llCrd: { x: 15_350_000, y: 46_980_000 }, urCrd: { x: 15_520_000, y: 47_120_000 } },
      center: [47.07, 15.44]
    },
    "linz" => {
      name: "Linz",
      label: "Linz",
      rect: { llCrd: { x: 14_200_000, y: 48_230_000 }, urCrd: { x: 14_380_000, y: 48_340_000 } },
      center: [48.30, 14.29]
    },
    "salzburg" => {
      name: "Salzburg",
      label: "Salzburg",
      rect: { llCrd: { x: 12_990_000, y: 47_760_000 }, urCrd: { x: 13_120_000, y: 47_840_000 } },
      center: [47.80, 13.05]
    },
    "innsbruck" => {
      name: "Innsbruck",
      label: "Innsbruck",
      rect: { llCrd: { x: 11_330_000, y: 47_230_000 }, urCrd: { x: 11_460_000, y: 47_300_000 } },
      center: [47.26, 11.39]
    }
  }.freeze

  def self.all
    CITIES
  end

  def self.find(key)
    CITIES[key.to_s]
  end

  def self.keys
    CITIES.keys
  end

  def self.enabled
    # Start with Wien only; add cities by uncommenting or via ENV
    keys_str = ENV.fetch("TRANSIT_CITIES", "wien")
    keys_str.split(",").map(&:strip).select { |k| CITIES.key?(k) }
  end
end
