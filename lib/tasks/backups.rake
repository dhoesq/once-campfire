namespace :backups do
  desc "Snapshot the SQLite DB(s) + Active Storage attachments and upload to Cloudflare R2 (inert if R2 env unset)"
  task export: :environment do
    summary = Backups::Export.run
    puts "[backup] #{summary.inspect}"
  end
end
