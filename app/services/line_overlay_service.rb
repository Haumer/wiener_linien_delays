class LineOverlayService
  def initialize(
    cache: Gtfs::LineCache.new,
    source_manager: Gtfs::SourceManager.new
  )
    @cache = cache
    @source_manager = source_manager
  end

  def call
    return @cache.read if @cache.available?

    return rebuild! if @source_manager.ready_for_compile?

    @cache.unavailable_payload
  rescue StandardError => e
    @cache.unavailable_payload("Line overlay is unavailable: #{e.message}")
  end

  def rebuild!(force: false)
    @source_manager.refresh!(force: force)
    payload = Gtfs::ViennaLineCompiler.new(sources: @source_manager.ready_sources).call
    @cache.write!(payload)
  end
end
