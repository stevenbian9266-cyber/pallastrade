PallasTrade::Core::Engine.add_routes do
  namespace :admin, path: PallasTrade.admin_path do
    # product catalog
    resources :option_types, except: :show do
      resources :option_values, only: [:update] do
        collection do
          get :select_options
        end
      end
    end
    resources :products do
      collection do
        get :select_options, defaults: { format: :json }
        post :search
        put :bulk_status_update
        put :bulk_add_to_taxons
        put :bulk_remove_from_taxons
        put :bulk_add_tags
        put :bulk_remove_tags
        # PRD-20260915-admin-bulk-operations-2：批量价格/库存/渠道（预览 → 确认）
        put :bulk_price_preview
        put :bulk_update_price
        put :bulk_inventory_preview
        put :bulk_adjust_inventory
        put :bulk_channels_preview
        put :bulk_update_channels
      end
      member do
        post :clone
      end
      resources :variants, only: [:edit, :update, :destroy]
      resources :digital_assets, except: [:show]
    end
    # variant search
    post 'variants/search'
    get 'variants/search', defaults: { format: :json }
    # product translations
    resources :product_translations, only: [:index]
    # catalog health（PRD-20260915-admin-catalog-health-v1）：商品健康待办中心（只读）
    get 'catalog_health', to: 'catalog_health#index', as: :catalog_health
    # duplicate detection（PRD-20260915-catalog-batch-d2-duplicate-detection）：重复商品候选 + 对比（只读）
    get 'duplicate_products', to: 'duplicate_products#index', as: :duplicate_products
    get 'duplicate_products/compare', to: 'duplicate_products#compare', as: :compare_duplicate_products
    # stock
    resources :stock_items, only: [:index, :update, :destroy]
    resources :stock_movements, only: [:index]
    resources :stock_transfers, except: [:edit, :update]
    # price lists
    resources :price_lists do
      resources :price_rules, only: [:new, :create, :edit, :update, :destroy]
      resources :products, only: [:index], controller: 'price_list_products' do
        collection do
          get :bulk_new
          post :bulk_create
          delete :bulk_destroy
        end
      end
      member do
        get :edit_prices
        put :activate
        put :deactivate
      end
    end
    # taxonomies and taxons
    resources :taxonomies do
      resources :taxons do
        member do
          put :reposition
        end
      end
    end
    resources :taxons, except: [:show] do |_taxon|
      resources :classifications, only: %i[index new create update destroy]
    end
    get '/taxons/select_options' => 'taxons#select_options', as: :taxons_select_options, defaults: { format: :json }
    get '/tags/select_options' => 'tags#select_options', as: :tags_select_options, defaults: { format: :json }
    get '/users/select_options' => 'users#select_options', as: :users_select_options, defaults: { format: :json }
    get '/stock_locations/select_options' => 'stock_locations#select_options', as: :stock_locations_select_options, defaults: { format: :json }
    resources :countries, only: [] do
      collection do
        get :select_options, defaults: { format: :json }
      end
      resources :states, only: [] do
        collection do
          get :select_options, defaults: { format: :json }
        end
      end
    end

    # media library
    resources :assets, only: [:create, :edit, :update, :destroy] do
      collection do
        delete :bulk_destroy
      end
    end

    # orders
    resources :checkouts, only: %i[index]
    resources :orders do
      member do
        post :resend
        put :cancel
        # P6 (2026-08-28): Admin 手动拆单（flag 灰度）
        get :split
        post :split, action: :split_create
        # P7 (2026-08-28): 父订单批量售后（flag 灰度）
        get :parent_order_returns
        post :parent_order_returns, action: :parent_order_returns_create
      end
      resource :shipping_address, except: [:show], controller: 'orders/shipping_address'
      resource :billing_address, except: [:show], controller: 'orders/billing_address'
      resource :contact_information, only: [:edit, :update], controller: 'orders/contact_information'
      resource :user, except: [:edit, :show], controller: 'orders/user'
      resources :shipments, only: [:edit, :update, :create], controller: 'shipments' do
        member do
          post :ship
          get :split
          post :transfer
        end
      end
      resources :line_items, except: :show do
        member do
          post :reset_digital_links_limit
        end
      end
      resources :customer_returns, except: [:index, :destroy], controller: 'orders/customer_returns'
      resources :return_authorizations, except: [:index, :destroy], controller: 'orders/return_authorizations'
      resources :payments, except: [:index, :show] do
        member do
          put :capture
          put :void
        end
        resources :refunds, only: [:new, :create, :edit, :update]
      end
      resources :payment_links, only: [:create], controller: 'orders/payment_links'
      resources :reimbursements, except: [:destroy, :index] do
        member do
          post :perform
        end
      end
      resources :adjustments, except: [:index, :show], controller: 'orders/adjustments' do
        member do
          put :toggle_state
        end
      end
      resources :order_promotions, only: [:new, :create, :destroy], controller: 'orders/order_promotions'
    end

    # customers
    resources :users do
      resources :store_credits
      resources :orders, only: [:index]
      resources :checkouts, only: [:index]
      resources :gift_cards

      collection do
        post :search
        post :bulk_add_tags
        post :bulk_remove_tags
      end
    end
    resources :customer_groups do
      collection do
        get :select_options, defaults: { format: :json }
      end
      resources :customer_group_users, only: [:index, :create, :destroy] do
        collection do
          get :bulk_new
          post :bulk_create
          delete :bulk_destroy
        end
      end
    end
    resources :newsletter_subscribers, only: [:index, :destroy]
    resources :addresses, except: [:index, :show]

    # promotions
    resources :promotions do
      collection do
        get :select_options
      end
      member do
        post :clone
      end
      resources :promotion_actions, as: :actions, except: [:index, :show]
      resources :promotion_rules, as: :rules, except: [:index, :show]
      resources :coupon_codes, only: :index
    end
    # PRD-20260911-promo-batch6 (PR-P9-2, D2=A): 促销分类后台 CRUD（安装级，无 store 维度）
    resources :promotion_categories, except: [:show]
    get 'search/option_values', defaults: { format: :json }, to: 'search#option_values'

    # gift cards
    resources :gift_cards
    # gift card batches
    resources :gift_card_batches, only: [:new, :create]

    # returns
    resources :return_authorizations, only: [:index, :destroy] do
      member do
        patch :cancel
      end
    end
    resources :customer_returns, only: :index
    resources :return_items, only: [:update]

    # translations
    resources :translations, only: [:edit, :update], path: '/translations/:resource_type'

    # metafields
    resources :metafields, only: [:edit, :update], path: '/metafields/:resource_type'
    resources :metafield_definitions, except: :show

    # json preview
    resources :json_previews, only: [:show], path: '/json_preview/:resource_type', as: :json_preview_resource

    # imports
    resources :imports, only: [:new, :create, :show] do
      resources :mappings, only: [:edit, :update], controller: 'import_mappings'
      resources :rows, only: :show, controller: 'import_rows'

      member do
        put :complete_mapping
      end
    end

    # audit log
    resources :exports, only: [:index, :new, :create, :show]

    # reporting
    resources :reports, only: [:index, :new, :create, :show]

    # profile settings
    resource :profile, controller: 'profile', only: %i[edit update]

    # PALLAS-CUSTOM: 多店铺管理（2026-08-17）——店铺列表/新建 + 切换
    resources :stores, only: [:index, :new, :create], controller: 'stores'
    post 'switch_store', to: 'stores#switch_store', as: :switch_store

    # store settings
    resource :store, only: [:edit, :update], controller: 'stores' do
      # needed for the getting started set customer support email step
      member do
        get :edit_emails
      end
      resources :role_users, only: [:destroy]
      resources :links, controller: 'page_links', only: [:create]
    end
    resources :policies, except: :show
    # PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915 切片3）—— provider 凭证体检（Test connection）
    # PALLAS-CUSTOM: D9（PRD-20260915-payments-d9 切片2）—— 凭据明文查看（reveal，owner 权限 + 审计）
    # PALLAS-CUSTOM: D11（PRD-20260916-payments-d11 切片1）—— 手动软置灰 / 解除（熔断兜底，入口级 + 审计）
    resources :payment_methods, except: :show do
      member do
        post :test_connection
        post :reveal_credential
        post :soft_disable
        post :soft_enable
      end
    end
    resources :shipping_methods, except: :show
    resources :shipping_categories, except: :show
    resources :channels, except: :show
    resources :store_credit_categories
    resources :tax_rates, except: :show
    resources :tax_categories, except: :show
    resources :reimbursement_types
    resources :refund_reasons, except: :show
    resources :return_authorization_reasons, except: :show
    resources :markets
    resources :zones
    resources :stock_locations, except: :show do
      member do
        put :mark_as_default
      end
    end
    # account management
    resources :roles, except: :show
    # PALLAS-CUSTOM: 可视化菜单配置模块（P4 权限体系重构）
    resources :menu_configs, only: [:index], controller: 'menu_configs'
    resources :invitations, except: [:edit, :update] do
      member do
        put :accept
        put :resend
      end
    end
    resources :admin_users do
      collection do
        get :select_options, defaults: { format: :json }
      end
    end

    # Action Text
    namespace :action_text do
      resources :video_embeds, only: [:create, :destroy]
    end

    # developer tools
    resources :api_keys, except: :destroy do
      member do
        put :revoke
      end
    end
    resources :webhook_endpoints do
      member do
        post :test
      end
      resources :webhook_deliveries, only: [:index, :show] do
        member do
          post :redeliver
        end
      end
    end
    # PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance）——
    # 入站 provider 事件流（Developers → Webhook Events）：只读检视 + 安全动作
    # （replay 复用 P0-2 重放链；quarantine 隔离未知事件；mark_processed 人工标记）。
    resources :webhook_events, only: [:index, :show], controller: 'webhook_events' do
      member do
        post :replay
        post :quarantine
        post :mark_processed
      end
    end
    resources :allowed_origins, except: :show
    resources :redirects
    resources :back_in_stock_subscriptions, only: [:index, :destroy]
        resources :abandoned_cart_notifications, only: [:index, :destroy] do
          post :run, on: :collection
        end
        resources :reviews, only: [:index, :destroy] do
          member do
            patch :approve
            patch :reject
          end
          collection do
            # Catalog F-3: bulk moderation (approve/reject up to 50 at a time).
            post :bulk
          end
        end

    # CMS blog posts
    resources :posts

    # Email management (Email top-level menu)
    resources :email_templates do
      member do
        get :preview
        post :test_send
      end
    end
    resources :email_logs, only: [:index, :show]
    resources :contact_messages, only: [:index, :show, :update] do
      member do
        post :resolve
      end
    end
    # TXN-P2-7 slice2: durable CommerceTransaction inspection + manual recovery
    resources :transactions, only: [:index, :show] do
      member do
        post :recover
      end
    end
    # PRD-20260910-promo-batch3c: 核销台账只读（Promotions → Redemptions）
    resources :promotion_redemptions, only: [:index, :show]
    # REV-P6-8a: Refund Ops —— durable Refund inspection（只读，Orders → Refunds）。
    # 与既有 payment 嵌套 refunds（new/create/edit/update）并存；controller 指向 refunds_ops。
    # REV-P6-8b: member retry（人工同键确定性重试）/ mark_review（人工标记复核）。
    resources :refunds, only: [:index, :show], controller: 'refunds_ops' do
      member do
        post :retry
        post :mark_review
      end
    end
    # REV-P6-8g: PaymentCombination 只读可视化（组合资金不可在 Admin 手改——无 new/edit/delete）
    resources :payment_combinations, only: [:index, :show]
    # REV-P6-8h: Payment Ops（只读；含组合 payment 与孤儿退款配对）——top-level /admin/payments
    resources :payments, only: [:index, :show], controller: 'payments_ops'
    # DSP-P7-7: Dispute Ops —— durable Dispute 只读检视 + 安全动作（Orders → Disputes）。
    # 只读优先：refresh / snapshot / dry_run 零写；recover（幂等收敛）与 mark_review（人工标记）是安全写动作。
    # DSP-P7-8: 新增两个**危险操作**（源计划 §67）——submit_evidence（向 provider 提交证据）与
    #   accept_dispute（接受争议，不可逆）；两者强制 permission(`:update`) + confirmation(前后端双重) + audit。
    resources :disputes, only: [:index, :show], controller: 'disputes_ops' do
      member do
        post :refresh
        post :dry_run
        post :recover
        post :snapshot
        post :mark_review
        # DSP-P7-10 B1：提交前校验（零写、零 provider I/O；仅给出阻断项与修复建议）
        post :precheck
        # DSP-P7-10 B2 / FR-005：证据草稿双人复核签核（append-only；提交前置条件）
        post :approve_draft
        # DSP-P7-8 危险操作（不可逆；无批量变体）
        post :submit_evidence
        post :accept_dispute
      end
    end
    # PALLAS-CUSTOM: D13 切片1（PRD-20260916-payments-d13-reconciliation-cases）——
    # 对账差异队列工作台（Orders → 对账队列）：reads + 运营动作（指派/备注/关单/重开）
    # + 按当前筛选导出 CSV。**零资金副作用**（只写案例表 + 审计）。
    resources :reconciliation_cases, only: [:index, :show] do
      collection do
        get :export
      end
      member do
        post :assign
        post :note
        post :mark_investigating
        post :mark_explained
        post :mark_fixed
        post :dismiss
        post :reopen
      end
    end
    # PALLAS-CUSTOM: D14 切片1（PRD-20260916-payments-d14-refund-approval）——
    # 退款审批（Orders → 退款审批）：待批队列 + 策略卡 + 第二人批准/拒绝（不能自批）。
    resources :refund_approvals, only: [:index] do
      collection do
        patch :policy
      end
      member do
        post :approve
        post :reject
      end
    end
    # PALLAS-CUSTOM: D13 切片2（PRD-20260916-payments-d13b-payout-ledger）——
    # 结算（Payout）台账（Orders → 结算台账）：列表/详情 + CSV 导入 + 重新匹配。
    # 导入/匹配只写台账表 + 案例表 + 审计（零资金副作用，不调 provider）。
    resources :payouts, only: %i[index show new] do
      collection do
        post :import
      end
      member do
        post :match
      end
    end
    # PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists）——
    # 风控名单（Orders → 风控名单）：筛选/计数 + 新增/续期/撤销 + CSV 批量导入/导出。
    # 只写名单表 + 审计（零资金副作用，不调 provider）。
    resources :risk_lists, only: %i[index create] do
      collection do
        post :import
        get :export
      end
      member do
        post :revoke
      end
    end
    get '/emails', to: 'emails#show', as: :emails
    patch '/emails', to: 'emails#update'
    post '/emails/test_send', to: 'emails#test_send', as: :emails_test_send
    get '/email_notification_scenarios', to: 'email_notification_scenarios#index', as: :email_notification_scenarios
    patch '/email_notification_scenarios', to: 'email_notification_scenarios#update', as: :email_notification_scenarios_update
    post '/email_notification_scenarios/test', to: 'email_notification_scenarios#test_send', as: :email_notification_scenarios_test

    # storefront setup
    get '/storefront', to: 'storefront#show', as: :storefront
    patch '/storefront', to: 'storefront#update'
    post '/storefront/allow_origin', to: 'storefront#allow_origin', as: :storefront_allow_origin

    # errors
    get '/forbidden', to: 'errors#show', code: 403, as: :forbidden
    if Rails.env.test?
      get '/errors', to: 'errors#show'
      get '/errors/:path', to: 'errors#show', as: :pathed_errors
    end

    # table columns (for session-based column selection)
    post 'table_columns', to: 'table_columns#update', as: :table_columns

    # bulk operations modal
    resources :bulk_operations, only: [:new]

    # dashboard
    resource :dashboard, controller: 'dashboard'
    get '/dashboard/analytics', to: 'dashboard#analytics', as: :dashboard_analytics
    get '/getting-started', to: 'dashboard#getting_started', as: :getting_started
    patch '/dismiss_updater_notice', to: 'dashboard#dismiss_updater_notice', as: :dismiss_updater_notice

    root to: 'dashboard#show'
  end

  get PallasTrade.admin_path, to: 'admin/dashboard#show', as: :admin
end
