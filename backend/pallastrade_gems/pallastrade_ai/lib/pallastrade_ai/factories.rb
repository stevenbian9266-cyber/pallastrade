# frozen_string_literal: true

# # PRD-20260813-admin-移除管理后台-integrations-菜单及相关逻辑
# # AI 模块解耦：加载 AI Provider 测试工厂（与 payment gem 的 factories 入口模式一致）
Dir["#{File.dirname(__FILE__)}/../pallastrade/testing_support/factories/**"].each do |f|
  load File.expand_path(f)
end
