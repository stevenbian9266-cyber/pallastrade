# frozen_string_literal: true

module PallasTrade
  module AI
    # Stores structured results or large files from AI runs.
    # Small outputs go in the `payload` JSONB; large outputs use ActiveStorage.
    class Artifact < BaseModel
      self.table_name = 'pallastrade_ai_artifacts'
      belongs_to :run, class_name: 'PallasTrade::AI::Run'

      has_one_attached :file

      validates :kind, presence: true
      validates :kind, inclusion: { in: %w[structured_output text_output file] }

      KINDS = %w[structured_output text_output file].freeze

      # Store a structured payload.
      def store_payload(data)
        update!(payload: data, content_type: 'application/json', kind: 'structured_output')
        update_checksum!
      end

      # Attach a file via ActiveStorage.
      def attach_output_file(io, filename:, content_type:)
        file.attach(io: io, filename: filename, content_type: content_type)
        update!(kind: 'file', content_type: content_type)
        update_checksum!
      end

      private

      def update_checksum!
        if payload.present?
          self.checksum = Digest::SHA256.hexdigest(payload.to_json)
          save!
        end
      end
    end
  end
end
