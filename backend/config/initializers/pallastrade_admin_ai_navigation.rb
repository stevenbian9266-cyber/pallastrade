# frozen_string_literal: true

# Register AI Tools navigation in the admin sidebar.
# PALLAS-CUSTOM: P6 导航架构重构 —— AI Tools 改为带子菜单的一级项，
# 顶级落地 = Overview（第一个子项），面包屑 AI Tools > Overview/Providers/...
Rails.application.config.after_initialize do
  PallasTrade.admin.navigation.sidebar.add :ai_tools,
    label: 'AI Tools',
    icon: 'robot',
    url: -> { PallasTrade.admin_ai_path },
    position: 80,
    landing: :overview,
    if: -> { can?(:manage, PallasTrade::AI::Setting) || can?(:read, PallasTrade::AI::Run) } do |ai|
    ai.add :overview,
           label: 'admin.ai.overview',
           url: -> { PallasTrade.admin_ai_path },
           position: 5,
           active: -> { controller_name == 'ai' && action_name == 'index' }
    ai.add :providers,
           label: :providers,
           url: -> { PallasTrade.admin_ai_providers_path },
           position: 10,
           active: -> { controller_name == 'ai' && action_name == 'providers' }
    ai.add :models,
           label: :models,
           url: -> { PallasTrade.admin_ai_models_path },
           position: 20,
           active: -> { controller_name == 'ai' && action_name == 'models' }
    ai.add :capabilities,
           label: :capabilities,
           url: -> { PallasTrade.admin_ai_capabilities_path },
           position: 30,
           active: -> { controller_name == 'ai' && action_name == 'capabilities' }
    ai.add :runs,
           label: :runs,
           url: -> { PallasTrade.admin_ai_runs_path },
           position: 40,
           active: -> { controller_name == 'ai' && action_name == 'runs' }
  end
end
