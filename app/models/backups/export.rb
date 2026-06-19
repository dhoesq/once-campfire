# frozen_string_literal: true

require "tmpdir"
require "open3"

# Disaster-recovery export: snapshots the live SQLite database(s) and the
# Active Storage attachment tree, then uploads them to Cloudflare R2 via the
# rclone binary (installed in the Dockerfile, no Ruby gem required).
#
# This class is INERT until R2 credentials are present in the environment. If any
# required R2 ENV var is blank it logs and returns without touching anything, so
# it cannot break the live app before R2 is provisioned.
#
# Run from a Resque worker (BackupJob) or manually (rake backups:export). Both
# the web and worker processes share the SQLite volume on Railway, so VACUUM INTO
# and the tar both see the live data.
module Backups
  class Export
    REQUIRED_ENV = %w[ R2_ENDPOINT R2_BUCKET R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY ].freeze
    BACKUP_PREFIX = "campfire-backups"

    def self.run
      new.run
    end

    def run
      unless configured?
        Rails.logger.info "[backup] R2 not configured, skipping"
        return { skipped: true }
      end

      timestamp = Time.now.utc.strftime("%Y%m%d-%H%M%S")
      year = Time.now.utc.strftime("%Y")
      remote_dir = "#{BACKUP_PREFIX}/#{year}/#{timestamp}"
      uploaded = []

      Dir.mktmpdir("campfire-backup") do |tmp|
        # 1. Consistent SQLite snapshot(s) via VACUUM INTO (safe on a live DB).
        snapshot_databases(tmp).each do |path|
          uploaded << upload(path, remote_dir)
        end

        # 2. Active Storage attachments as a single gzipped tarball.
        if (archive = archive_storage(tmp))
          uploaded << upload(archive, remote_dir)
        end
      end

      summary = { remote_dir: remote_dir, files: uploaded }
      Rails.logger.info "[backup] complete: #{summary_line(uploaded, remote_dir)}"
      summary
    end

    private
      def configured?
        REQUIRED_ENV.all? { |key| ENV[key].present? }
      end

      # Produce a consistent on-disk copy of each SQLite database configured for
      # the current environment. VACUUM INTO is the SQLite-blessed way to copy a
      # live database without locking writers for long or risking a torn file.
      # Returns an array of local file paths.
      def snapshot_databases(tmp)
        snapshots = []

        each_sqlite_connection do |name, connection|
          dest = File.join(tmp, "#{name}.sqlite3")
          # VACUUM INTO refuses to overwrite an existing file.
          File.delete(dest) if File.exist?(dest)
          quoted = dest.gsub("'", "''")
          connection.execute("VACUUM INTO '#{quoted}'")
          if File.exist?(dest)
            snapshots << dest
            Rails.logger.info "[backup] snapshotted #{name} (#{File.size(dest)} bytes)"
          else
            Rails.logger.warn "[backup] VACUUM INTO produced no file for #{name}, skipping"
          end
        end

        snapshots
      end

      # Yield [logical_name, connection] for each SQLite database in this env.
      # Campfire ships a single primary SQLite DB, but this iterates the
      # configured connections so additional SQLite DBs are picked up too.
      def each_sqlite_connection
        configs = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)

        configs.each do |config|
          next unless sqlite?(config)

          name = config.respond_to?(:name) ? config.name : "primary"
          ActiveRecord::Base.connected_to(role: ActiveRecord::Base.current_role, shard: name.to_sym) do
            yield name, ActiveRecord::Base.connection
          end
        rescue StandardError
          # Fall back to the default connection (single-DB apps like Campfire).
          connection = ActiveRecord::Base.connection
          yield name, connection if sqlite_connection?(connection)
        end
      rescue StandardError => e
        # Last-resort: just snapshot the default connection if it is SQLite.
        Rails.logger.warn "[backup] connection enumeration failed (#{e.class}: #{e.message}); using default connection"
        connection = ActiveRecord::Base.connection
        yield "primary", connection if sqlite_connection?(connection)
      end

      def sqlite?(config)
        adapter = config.respond_to?(:adapter) ? config.adapter : config.config["adapter"]
        adapter.to_s.start_with?("sqlite")
      end

      def sqlite_connection?(connection)
        connection.adapter_name.to_s.downcase.include?("sqlite")
      end

      # tar+gzip the Active Storage local disk root. Excludes the SQLite db
      # subdirectory (the VACUUM copy is the canonical DB backup) in case the DB
      # ever lives under the same storage parent. Returns the archive path, or
      # nil if there is nothing to archive.
      def archive_storage(tmp)
        root = active_storage_root
        unless root && Dir.exist?(root)
          Rails.logger.info "[backup] no Active Storage directory at #{root.inspect}, skipping attachments"
          return nil
        end

        archive = File.join(tmp, "storage.tar.gz")
        parent = File.dirname(root)
        base = File.basename(root)

        # Archive only the Active Storage files dir (base). The SQLite DB lives in
        # a sibling dir (storage/db), not under base, so it is already excluded —
        # no glob excludes (which would wrongly drop user attachments named *.sqlite3).
        ok = system(
          "tar", "-czf", archive,
          "-C", parent, base
        )

        unless ok && File.exist?(archive)
          Rails.logger.warn "[backup] tar of #{root} failed, skipping attachments"
          return nil
        end

        Rails.logger.info "[backup] archived attachments from #{root} (#{File.size(archive)} bytes)"
        archive
      end

      def active_storage_root
        service = ActiveStorage::Blob.service
        return nil unless service.respond_to?(:root)
        service.root.to_s
      rescue StandardError => e
        Rails.logger.warn "[backup] could not resolve Active Storage root (#{e.class}: #{e.message})"
        nil
      end

      # Upload a single local file to R2 with an on-the-fly S3 remote (no rclone
      # config file). Secrets are passed as CLI flags from ENV but never logged.
      # Raises on failure so the job surfaces the error.
      def upload(local_path, remote_dir)
        name = File.basename(local_path)
        destination = ":s3:#{ENV['R2_BUCKET']}/#{remote_dir}/#{name}"

        cmd = [
          "rclone", "copyto", local_path, destination,
          "--s3-provider", "Cloudflare",
          "--s3-access-key-id", ENV["R2_ACCESS_KEY_ID"],
          "--s3-secret-access-key", ENV["R2_SECRET_ACCESS_KEY"],
          "--s3-endpoint", ENV["R2_ENDPOINT"],
          "--s3-no-check-bucket"
        ]

        _stdout, stderr, status = Open3.capture3(*cmd)

        unless status.success?
          # Do not include the command (it carries secrets) in the message.
          raise "rclone upload failed for #{name} (exit #{status.exitstatus}): #{stderr.to_s.strip}"
        end

        size = File.size(local_path)
        Rails.logger.info "[backup] uploaded #{name} (#{size} bytes) to #{BACKUP_PREFIX}/#{remote_dir.split('/').last(2).join('/')}"
        { name: name, bytes: size }
      end

      def summary_line(uploaded, remote_dir)
        total = uploaded.sum { |f| f[:bytes].to_i }
        "#{uploaded.size} file(s), #{total} bytes -> #{remote_dir}"
      end
  end
end
