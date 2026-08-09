# frozen_string_literal: true

# One-off / idempotent migration of blobs from the local Disk service to Aliyun
# OSS. Run on the server where OSS_* env vars are set:
#
#   bundle exec rake pallastrade:storage:mirror_to_oss
#
# Idempotent: blobs already present in the OSS bucket are skipped, and every
# blob whose object exists in OSS gets its `service_name` repointed to :aliyun
# so reads come from OSS (not the local Disk volume).
namespace :pallastrade do
  namespace :storage do
    desc 'Mirror blobs from local Disk storage to Aliyun OSS and repoint service_name (idempotent)'
    task mirror_to_oss: :environment do
      source = ActiveStorage::Blob.services.fetch(:local)
      target = ActiveStorage::Blob.services.fetch(:aliyun)

      total = ActiveStorage::Blob.count
      done = 0
      skipped = 0
      repointed = 0
      failed = 0

      puts "Mirroring #{total} blobs from :local to :aliyun..."

      ActiveStorage::Blob.find_each do |blob|
        key = blob.key
        begin
          if target.exist?(key)
            skipped += 1
          else
            source.open(key, checksum: blob.checksum) do |file|
              target.upload(
                key,
                file,
                checksum: blob.checksum,
                filename: blob.filename.to_s,
                content_type: blob.content_type
              )
            end
          end

          unless blob.service_name == 'aliyun'
            blob.update_column(:service_name, 'aliyun')
            repointed += 1
          end
          done += 1
        rescue StandardError => e
          failed += 1
          warn "  ERROR #{key}: #{e.class}: #{e.message}"
        end

        puts "  [#{done}/#{total}] repointed=#{repointed} failed=#{failed}" if (done % 50).zero?
      end

      puts "Mirror complete: total=#{total} processed=#{done} repointed=#{repointed} failed=#{failed}"
    end
  end
end
