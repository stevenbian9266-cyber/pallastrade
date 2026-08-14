# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        # Admin API serializer for {PallasTrade::ConfigItem}.
        #
        # Security contract:
        #   * non-secret items expose `value` (plaintext);
        #   * secret items NEVER expose plaintext — only `secret_configured`,
        #     `secret_hint` (masked) and `secret_rotated_at`.
        class ConfigItemSerializer < V3::BaseSerializer
          typelize key: :string,
                   group: :string,
                   value_type: :string,
                   value: [:string, nullable: true],
                   secret_configured: [:boolean, nullable: true],
                   secret_hint: [:string, nullable: true],
                   secret_rotated_at: [:string, nullable: true],
                   description: [:string, nullable: true],
                   default_value: [:string, nullable: true]

          attributes :key, :group, :value_type, :description, :default_value,
                     updated_at: :iso8601

          # Plaintext only for non-secret items.
          attribute :value do |item|
            item.secret? ? nil : item.raw_value
          end

          attribute :secret_configured do |item|
            item.secret? ? item.configured? : nil
          end

          attribute :secret_hint do |item|
            item.secret? ? item.key_hint_display : nil
          end

          attribute :secret_rotated_at do |item|
            item.secret? ? item.rotated_at&.iso8601 : nil
          end
        end
      end
    end
  end
end
