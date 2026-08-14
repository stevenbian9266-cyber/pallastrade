# frozen_string_literal: true

module PallasTrade
  module Admin
    # Config Center admin — manage unified config items (including encrypted
    # secrets) from the Settings area.
    class ConfigItemsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern

      helper_method :suggested_env_keys

      # Known environment variables that commonly back third-party integrations.
      def suggested_env_keys
        %w[
          OSS_ACCESS_KEY_ID OSS_SECRET_ACCESS_KEY OSS_ENDPOINT
          STRIPE_SECRET_KEY STRIPE_PUBLISHABLE_KEY STRIPE_WEBHOOK_SECRET
          TURNSTILE_SITE_KEY TURNSTILE_SECRET_KEY
          ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
        ].select { |k| ENV[k].present? }
      end

      # POST /admin/config_items
      # Routes the submitted `value` to the correct lane (encrypted for secret
      # items) via assign_value.
      def create
        invoke_callbacks(:create, :before)
        set_created_by
        @object.attributes = permitted_resource_params
        apply_value_param(@object)
        if @object.save
          invoke_callbacks(:create, :after)
          flash[:success] = message_after_create
          redirect_to location_after_create, status: :see_other
        else
          invoke_callbacks(:create, :fails)
          render action: :new, status: :unprocessable_content
        end
      end

      # PATCH /admin/config_items/:id
      # Blank `value` on a secret item leaves the secret unchanged.
      def update
        invoke_callbacks(:update, :before)
        @object.assign_attributes(permitted_resource_params)
        apply_value_param(@object)
        if @object.save
          invoke_callbacks(:update, :after)
          flash[:success] = message_after_update
          redirect_to location_after_save, status: :see_other
        else
          invoke_callbacks(:update, :fails)
          render action: :edit, status: :unprocessable_content
        end
      end

      # POST /admin/config_items/import
      # Server-side import: reads known ENV vars (e.g. OSS_ACCESS_KEY_ID) into
      # Config Center items. Never round-trips secret values through the form.
      def import
        env_keys = Array(params[:env_keys])
        imported = []
        skipped = 0
        env_keys.each do |env_key|
          value = ENV[env_key.to_s]
          if value.blank?
            skipped += 1
            next
          end

          key = env_key.to_s.downcase.tr('_', '.')
          item = scope.find_or_initialize_by(key: key)
          if item.configured?
            skipped += 1
            next
          end

          item.group = 'imported'
          item.value_type = infer_value_type(env_key)
          item.description = "Imported from #{env_key}"
          item.assign_value(value)
          imported << { key: key, saved: item.save, errors: item.errors.full_messages }
        end

        saved = imported.count { |r| r[:saved] }
        flash[:success] = "Imported #{saved} item(s)#{skipped.positive? ? ", skipped #{skipped}" : ''}"
        redirect_to PallasTrade.admin_config_items_path, status: :see_other
      end

      private

      def model_class
        PallasTrade::ConfigItem
      end

      def scope
        current_store.config_items
      end

      def object_name
        'config_item'
      end

      # `key` / `value_type` are create-only; updates only touch descriptions and
      # values (value handled via apply_value_param).
      def permitted_resource_params
        base = params.require(:config_item).permit(:description, :default_value, :group)
        return base if action_name == 'update'

        base.merge(params.require(:config_item).permit(:key, :value_type))
      end

      def location_after_create
        PallasTrade.admin_config_items_path
      end

      alias location_after_save location_after_create

      def update_turbo_stream_enabled?
        false
      end

      def apply_value_param(item)
        return unless params.dig(:config_item, :value).present? || (params.dig(:config_item, :value).nil? == false && action_name == 'create')

        value = params.dig(:config_item, :value)
        # Blank value on an existing secret item = leave unchanged.
        return if value.blank? && item.secret? && item.persisted?

        item.assign_value(value)
      end

      # Infer the Config Center value type from an ENV variable name.
      def infer_value_type(env_key)
        if env_key.to_s =~ /(SECRET|KEY|TOKEN|PASSWORD|CREDENTIAL)/
          'secret'
        else
          'string'
        end
      end
    end
  end
end
