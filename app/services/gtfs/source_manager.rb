require "fileutils"
require "open-uri"
require "open3"

module Gtfs
  class SourceManager
    def initialize(sources: SourceCatalog.sources)
      @sources = sources
    end

    def refresh!(force: false)
      @sources.each do |source|
        download!(source, force: force)
        extract!(source, force: force)
      end
    end

    def ready_sources
      @sources.filter_map do |source|
        ready_extract_dir = resolved_extract_dir(source)
        next unless ready_extract_dir

        source.merge(extract_dir: ready_extract_dir)
      end
    end

    def ready_for_compile?
      ready_sources.any?
    end

    private

    def download!(source, force:)
      archive_path = source.fetch(:archive_path)
      return archive_path if archive_path.exist? && !force

      FileUtils.mkdir_p(archive_path.dirname)
      temp_path = archive_path.sub_ext(".tmp")

      URI.open(source.fetch(:url), "rb", read_timeout: 120, open_timeout: 30) do |remote|
        File.open(temp_path, "wb") do |local|
          IO.copy_stream(remote, local)
        end
      end

      FileUtils.mv(temp_path, archive_path)
      archive_path
    ensure
      FileUtils.rm_f(temp_path) if temp_path && temp_path.exist?
    end

    def extract!(source, force:)
      archive_path = source.fetch(:archive_path)
      extract_dir = source.fetch(:extract_dir)
      ready_extract_dir = resolved_extract_dir(source)

      return ready_extract_dir if ready_extract_dir && !force && extracted_up_to_date?(archive_path, ready_extract_dir)

      FileUtils.mkdir_p(extract_dir)
      FileUtils.chmod_R(0o755, extract_dir) if extract_dir.exist?
      stdout, stderr, status = Open3.capture3("unzip", "-oq", archive_path.to_s, "-d", extract_dir.to_s)
      return resolved_extract_dir(source) if status.success?

      raise "GTFS extract failed for #{source.fetch(:label)}: #{stderr.presence || stdout.presence || 'unzip returned a non-zero status'}"
    end

    def extracted?(source)
      resolved_extract_dir(source).present?
    end

    def extracted_up_to_date?(archive_path, extract_dir)
      newest_extracted_at = SourceCatalog::REQUIRED_FILES.filter_map do |filename|
        path = extract_dir.join(filename)
        path.mtime if path.exist?
      end.max

      newest_extracted_at && newest_extracted_at >= archive_path.mtime
    end

    def resolved_extract_dir(source)
      extract_dir = source.fetch(:extract_dir)
      return extract_dir if required_files_present?(extract_dir)
      return unless extract_dir.exist?

      extract_dir.children.find do |path|
        path.directory? && required_files_present?(path)
      end
    end

    def required_files_present?(directory)
      SourceCatalog::REQUIRED_FILES.all? do |filename|
        directory.join(filename).exist?
      end
    end
  end
end
