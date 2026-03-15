namespace :transit do
  desc "Download the source GTFS archives for the Vienna line overlay"
  task download_gtfs: :environment do
    Gtfs::SourceManager.new.refresh!(force: false)
    puts "GTFS archives downloaded and extracted."
  end

  desc "Compile the Vienna tram, bus, S-Bahn, and rail line overlay cache"
  task build_lines: :environment do
    payload = LineOverlayService.new.rebuild!(force: false)
    puts "Built #{payload.dig(:meta, :line_count)} line features."
  end

  desc "Compile the Vienna tram, bus, and rail stop overlay cache"
  task build_stops: :environment do
    payload = StopOverlayService.new.rebuild!(force: false)
    puts "Built #{payload.dig(:meta, :stop_count)} stop entries."
  end

  desc "Download/extract GTFS data and rebuild the Vienna line overlay cache"
  task refresh_lines: :environment do
    payload = LineOverlayService.new.rebuild!(force: true)
    puts "Built #{payload.dig(:meta, :line_count)} line features."
  end

  desc "Download/extract GTFS data and rebuild the Vienna stop overlay cache"
  task refresh_stops: :environment do
    payload = StopOverlayService.new.rebuild!(force: true)
    puts "Built #{payload.dig(:meta, :stop_count)} stop entries."
  end
end
