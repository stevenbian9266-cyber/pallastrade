# frozen_string_literal: true

# Register AI Tools navigation in the admin sidebar.
Rails.application.config.after_initialize do
  PallasTrade.admin.navigation.sidebar.add :ai_tools,
    label: 'AI Tools',
    icon: 'robot',
    url: -> { PallasTrade.admin_ai_path },
    position: 90,
    if: -> { can?(:manage, PallasTrade::AI::Setting) || can?(:read, PallasTrade::AI::Run) }
end
