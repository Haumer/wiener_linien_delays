class CityConfig
  # Top 20 Austrian cities by population
  # Bounding boxes are approximate rectangles covering the urban transit area
  # Coordinates are HAFAS format: degrees * 1_000_000
  CITIES = {
    "wien" => {
      name: "Wien", population: 1_982_000,
      rect: { llCrd: { x: 16_180_000, y: 48_110_000 }, urCrd: { x: 16_580_000, y: 48_330_000 } },
      center: [48.21, 16.37]
    },
    "graz" => {
      name: "Graz", population: 295_000,
      rect: { llCrd: { x: 15_350_000, y: 46_980_000 }, urCrd: { x: 15_520_000, y: 47_120_000 } },
      center: [47.07, 15.44]
    },
    "linz" => {
      name: "Linz", population: 210_000,
      rect: { llCrd: { x: 14_200_000, y: 48_230_000 }, urCrd: { x: 14_380_000, y: 48_340_000 } },
      center: [48.30, 14.29]
    },
    "salzburg" => {
      name: "Salzburg", population: 157_000,
      rect: { llCrd: { x: 12_990_000, y: 47_760_000 }, urCrd: { x: 13_120_000, y: 47_840_000 } },
      center: [47.80, 13.05]
    },
    "innsbruck" => {
      name: "Innsbruck", population: 132_000,
      rect: { llCrd: { x: 11_330_000, y: 47_230_000 }, urCrd: { x: 11_460_000, y: 47_300_000 } },
      center: [47.26, 11.39]
    },
    "klagenfurt" => {
      name: "Klagenfurt", population: 103_000,
      rect: { llCrd: { x: 14_240_000, y: 46_580_000 }, urCrd: { x: 14_360_000, y: 46_660_000 } },
      center: [46.62, 14.31]
    },
    "villach" => {
      name: "Villach", population: 65_000,
      rect: { llCrd: { x: 13_800_000, y: 46_570_000 }, urCrd: { x: 13_920_000, y: 46_660_000 } },
      center: [46.61, 13.85]
    },
    "wels" => {
      name: "Wels", population: 63_000,
      rect: { llCrd: { x: 13_980_000, y: 48_130_000 }, urCrd: { x: 14_100_000, y: 48_200_000 } },
      center: [48.16, 14.03]
    },
    "st_poelten" => {
      name: "St. Pölten", population: 56_000,
      rect: { llCrd: { x: 15_580_000, y: 48_170_000 }, urCrd: { x: 15_720_000, y: 48_240_000 } },
      center: [48.20, 15.63]
    },
    "dornbirn" => {
      name: "Dornbirn", population: 50_000,
      rect: { llCrd: { x: 9_700_000, y: 47_370_000 }, urCrd: { x: 9_810_000, y: 47_440_000 } },
      center: [47.41, 9.74]
    },
    "wiener_neustadt" => {
      name: "Wiener Neustadt", population: 47_000,
      rect: { llCrd: { x: 16_200_000, y: 47_780_000 }, urCrd: { x: 16_310_000, y: 47_830_000 } },
      center: [47.81, 16.25]
    },
    "steyr" => {
      name: "Steyr", population: 39_000,
      rect: { llCrd: { x: 14_380_000, y: 48_020_000 }, urCrd: { x: 14_470_000, y: 48_070_000 } },
      center: [48.04, 14.42]
    },
    "feldkirch" => {
      name: "Feldkirch", population: 36_000,
      rect: { llCrd: { x: 9_560_000, y: 47_210_000 }, urCrd: { x: 9_660_000, y: 47_280_000 } },
      center: [47.24, 9.60]
    },
    "bregenz" => {
      name: "Bregenz", population: 34_000,
      rect: { llCrd: { x: 9_700_000, y: 47_470_000 }, urCrd: { x: 9_800_000, y: 47_540_000 } },
      center: [47.50, 9.75]
    },
    "leonding" => {
      name: "Leonding", population: 29_000,
      rect: { llCrd: { x: 14_210_000, y: 48_250_000 }, urCrd: { x: 14_290_000, y: 48_300_000 } },
      center: [48.28, 14.25]
    },
    "klosterneuburg" => {
      name: "Klosterneuburg", population: 28_000,
      rect: { llCrd: { x: 16_280_000, y: 48_290_000 }, urCrd: { x: 16_370_000, y: 48_340_000 } },
      center: [48.31, 16.33]
    },
    "baden" => {
      name: "Baden bei Wien", population: 26_000,
      rect: { llCrd: { x: 16_180_000, y: 47_980_000 }, urCrd: { x: 16_270_000, y: 48_030_000 } },
      center: [48.01, 16.23]
    },
    "wolfsberg" => {
      name: "Wolfsberg", population: 25_000,
      rect: { llCrd: { x: 14_780_000, y: 46_800_000 }, urCrd: { x: 14_880_000, y: 46_860_000 } },
      center: [46.84, 14.84]
    },
    "leoben" => {
      name: "Leoben", population: 25_000,
      rect: { llCrd: { x: 15_050_000, y: 47_350_000 }, urCrd: { x: 15_150_000, y: 47_410_000 } },
      center: [47.38, 15.09]
    },
    "krems" => {
      name: "Krems an der Donau", population: 25_000,
      rect: { llCrd: { x: 15_560_000, y: 48_380_000 }, urCrd: { x: 15_660_000, y: 48_440_000 } },
      center: [48.41, 15.61]
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
    keys_str = ENV.fetch("TRANSIT_CITIES", "wien")
    keys_str.split(",").map(&:strip).select { |k| CITIES.key?(k) }
  end
end
