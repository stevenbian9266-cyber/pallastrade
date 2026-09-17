module PallasTrade
  module Api
    module V3
      class PolicySerializer < BaseSerializer
        typelize name: :string, slug: :string,
                 body: [:string, nullable: true], body_html: [:string, nullable: true],
                 merchant_return_policy: '{ category: string, days: number | null, ' \
                                         'method: string | null, fees: string | null, ' \
                                         'countries: string[] } | null'

        attributes :name, :slug

        attribute :body do |policy|
          policy.body&.to_plain_text
        end

        attribute :body_html do |policy|
          policy.body&.body&.to_s.to_s
        end

        # 结构化退货条款（PRD-20260917-catalog-json-ld-phase2 FR-005）——
        # 商品页结构化数据 `hasMerchantReturnPolicy` 的数据源。
        #
        # 只在**退货政策**上下发：条款描述的就是退货政策本身，别的政策（隐私/配送/
        # 条款）即使被写入过值也不该出现在它们的响应里 —— 否则会把一条挂错地方的数据
        # 当成全店退货政策发布出去。
        #
        # 且只有条款**完整**时才有值；未配置或残缺 → nil，前台据此**整体省略**
        # `hasMerchantReturnPolicy`。宁可缺字段，也不要发布一条编造的退货政策：
        # 一条「有限窗口但没说多少天」的残缺政策会被搜索引擎判为结构化数据错误，
        # 比不输出更糟。
        #
        # 归一化（脏枚举归空、非正天数归 nil、国家码去重大写）在模型层
        # `Policy#merchant_return_policy_terms` 完成，这里只做选择与序列化。
        attribute :merchant_return_policy do |policy|
          policy.returns_policy? ? policy.merchant_return_policy_terms : nil
        end

      end
    end
  end
end
