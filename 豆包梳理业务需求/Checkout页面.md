# Pallastrade 独立站 Checkout 页面产品需求文档（PRD）

| 项目 | 内容 |
|------|------|
| 文档版本 | v1.1 |
| 页面类型 | One-page checkout 单页结账 |
| 文档状态 | 需求评审稿 |
| 适用端 | PC 端 / 响应式移动端 |

---

## 一、产品概述

### 1.1 页面定位
Checkout 页面是用户从购物车到完成支付的核心转化页面，采用单页结账（One-page checkout）模式，将联系信息、配送地址、配送方式、增值服务、支付五大模块集中在同一页面完成，减少页面跳转带来的流失。

### 1.2 核心目标
- 降低结账操作步骤，提升支付转化率
- 实时展示订单金额变动，建立价格透明感
- 通过增值服务（Worry-Free Purchase）提升客单价
- 通过信息保存功能提升复购用户的结账效率

### 1.3 用户旅程
用户进入 Checkout 页面 → 填写/确认联系信息 → 确认/新增配送地址 → 选择配送方式 → 选择增值服务（可选）→ 选择支付方式并填写 → 决定是否保存信息 → 点击 Pay now 完成支付

---

## 二、页面整体结构

### 2.1 布局
采用左右双栏布局：

| 区域 | 占比 | 内容 |
|------|------|------|
| 左栏 | 70% | 表单填写主区域（Contact → Delivery → Shipping → Add-ons → Payment → Save info → Pay now） |
| 右栏 | 30% | 订单摘要侧边栏（商品列表、折扣码、价格明细、购买权益） |

右栏订单摘要采用吸顶（sticky）定位，用户滚动左栏表单时始终可见金额变动。

### 2.2 模块顺序（左栏自上而下）
1. Contact 联系信息
2. Delivery address 配送地址
3. Shipping method 配送方式
4. Add-ons 增值服务
5. Payment 支付
6. Save information 信息保存
7. Pay now 按钮 + 政策链接

---

## 三、功能模块详细需求

### 3.1 顶部全局栏

**功能能力**
- 展示站点 Logo，点击可返回首页
- 展示安全结账标识（Secure Checkout），传递支付安全感

**交互**
- Logo 可点击跳转首页
- 安全标识为静态展示，无交互

---

### 3.2 Contact 联系信息

**功能能力**
- Email 邮箱输入框，支持预填充（已登录用户自动带入账号邮箱）
- Sign in 登录链接、Sign up 注册链接
- 邮件营销订阅复选框："Email me with news and offers"，默认勾选

**交互**
- 用户输入邮箱，失焦时校验邮箱格式
- 点击 Sign in / Sign up 跳转对应页面（或弹出登录/注册浮层）
- 复选框可自由勾选/取消

**异常提醒**
- 邮箱格式错误：输入框下方提示"Please enter a valid email address"
- 点击 Pay now 时邮箱为空：弹窗提示"Please enter your email address."

---

### 3.3 Delivery address 配送地址

**功能能力**
- 展示已保存的默认地址卡片（带 Default 标签），包含姓名、详细地址、城市/州/邮编、国家、电话
- 支持新增地址：点击"+ Add a new address"展开完整地址表单
- 新增地址表单字段：
  - 国家/地区下拉选择框
  - First name / Last name 姓名（双列并排）
  - Address 详细地址
  - Apartment, suite etc. (optional) 公寓/单元（选填，标注 optional）
  - City / State / ZIP code（三列并排，State 为下拉选择）
  - Phone 联系电话
  - 短信营销订阅复选框："Send me exclusive offers via text message and call"

**交互**
- 点击"+ Add a new address"按钮，表单展开，按钮文字变为"− Collapse address form"；再次点击收起
- 国家选择后，State 下拉选项应联动更新为对应国家的省/州列表
- 表单字段失焦时逐项校验必填项

**异常提醒**
- 必填字段为空时提交：对应输入框标红并提示必填
- 电话格式错误：提示"Please enter a valid phone number"
- 地址无法被物流系统识别：提示"Address not recognized, please check and re-enter"

---

### 3.4 Shipping method 配送方式

**功能能力**
- 黄色警告提示框："The shipping options have changed for your order. Review your selection."
- 配送方案卡片：Standard Shipping【FREE】，附带送达时效 3-7 Business Days
- 小字说明 + 跳转链接："Some products in this order only support 'Standard Shipping'. View more."

**交互**
- 配送方式为单选，当前仅 Standard Shipping 可选，默认选中
- 点击"View more"跳转至配送说明页面或弹出说明浮层
- 警告提示框为静态展示，可关闭（后续扩展）

**异常提醒**
- 当订单中商品的配送选项发生变化（如某商品从支持快递变为仅支持标准配送）时，展示黄色警告框，提醒用户重新确认选择
- 当所选配送方式无法配送到当前地址时：提示"Shipping method not available for this address"

---

### 3.5 Add-ons 增值服务

**功能能力**
- 增值服务单选选项：Worry-Free Purchase
- 服务说明：Extended protection covering accidental damage, loss, and theft for 2 years. Priority replacement service included.
- 系统占位提示："Value-added service not yet integrated — price recalculation pending system connection"

**交互**
- 点击选项卡片，单选选中/取消切换，选中时卡片高亮
- 选中后应触发订单金额重新计算（当前为占位，未接入）

**异常提醒**
- 增值服务未接入时：展示占位提示，告知用户该服务暂不可用或价格待确认

---

### 3.6 Payment 支付

**功能能力**
- 安全提示文案："All transactions are secure and encrypted."（带锁图标）
- 支付方式单选组：
  - **Credit card 信用卡**（默认选中）：
    - Card number 卡号输入框
    - Expiration date 有效期 / Security code CVV 安全码（双列并排）
    - Name on card 持卡人姓名
    - 复选框："Use shipping address as billing address"（默认勾选）
    - Billing address 账单地址完整表单（国家、姓名、地址、城市、州、邮编、电话），勾选复用地址时隐藏
    - 支付渠道图标展示（VISA / MasterCard / AMEX）
  - **PayPal**（占位）：
    - 选中后展示提示："You will be redirected to PayPal to complete your purchase securely."

**交互**
- 点击支付方式头部切换，选中方式展开表单，未选中方式收起
- 卡号输入时自动按 4 位一组空格分隔（如 1234 5678 9012 3456）
- 有效期输入时自动格式化为 MM / YY
- 勾选"Use shipping address as billing address"时，账单地址表单隐藏；取消勾选时展开
- PayPal 选中后不展示表单，仅展示跳转提示

**异常提醒**
- 卡号位数不足或 Luhn 校验失败：提示"Please enter a valid card number"
- 有效期已过期：提示"Card has expired"
- CVV 位数错误：提示"Please enter a valid security code"
- 持卡人姓名为空：提示必填
- 支付处理失败：展示错误提示，保留用户已填信息，允许重试

---

### 3.7 Save information 信息保存

**功能能力**
- 说明文本："Save my information for a faster checkout"
- 两个操作按钮：
  - **Save**（主按钮）：保存当前填写的信息
  - **Not now**（次按钮）：本次不保存

**交互**
- 点击 Save：按钮区域变为绿色确认提示"✓ Information saved for faster checkout next time."
- 点击 Not now：整个区块置灰禁用，表示本次跳过

**异常提醒**
- 未登录用户点击 Save 时：应引导登录或创建账号（信息保存需关联用户账号）

---

### 3.9 右栏：Order summary 订单摘要

#### 3.9.1 商品列表

**功能能力**
- 展示订单中所有商品，每个商品包含：
  - 商品缩略图
  - 商品名称
  - 规格参数（如颜色、型号、版本等）
  - 单价
  - 数量角标（缩略图右上角展示数量）

**交互**
- 商品信息为只读展示，不可在结账页修改数量或删除商品
- 点击商品名称/图片可跳转商品详情页（新标签页）

#### 3.9.2 折扣码模块

**功能能力**
- 输入框："Discount code or gift card"
- Apply 应用按钮
- 已使用折扣码条目：展示折扣码名称、优惠金额、删除按钮（×）

**交互**
- 输入折扣码后点击 Apply（或回车），校验通过后应用
- 应用成功后：输入框清空，已应用折扣码条目展示在下方，价格明细中增加 Discount 行，底部展示 TOTAL SAVINGS
- 点击删除按钮（×）：移除折扣码，价格恢复，Discount 行和 TOTAL SAVINGS 隐藏
- 同一时间仅支持一个折扣码（应用新折扣码前需先移除旧的，或新码自动替换旧码）

**异常提醒**
- 折扣码无效/过期/不适用：弹窗提示"Invalid discount code"
- 折扣码已达使用上限：提示"This code has reached its usage limit"
- 订单金额不满足折扣码最低消费要求：提示"Minimum order amount not met"

#### 3.9.3 价格明细

**功能能力**
- Subtotal 商品小计
- Shipping 运费（当前为 FREE，绿色展示）
- Estimated taxes 预估税费
- Discount 折扣（有折扣时展示，绿色）
- Total 订单总金额（加粗，分隔线突出）
- TOTAL SAVINGS 总优惠节省金额（绿色背景条，有折扣时展示）

**交互**
- 价格明细随折扣码应用/移除、增值服务选择等操作实时更新
- 所有金额保留两位小数

#### 3.9.4 Why Buy From Us 购买权益

**功能能力**
- 四项购买权益，图标 + 文字：
  - 30-Day Money-Back Guarantee 30天退款保障
  - Hassle-Free Warranty 无忧质保
  - Lifetime Customer Support 终身客户支持
  - Fast, Free Shipping 快速免运费

**交互**
- 静态展示，无交互（或可点击跳转对应说明页）

---

## 四、全局交互规范

### 4.1 表单交互
- 所有必填字段在失焦时校验，错误信息展示在输入框下方
- 输入框聚焦时边框高亮（品牌色），提供清晰的输入定位
- 下拉选择器使用统一的自定义箭头样式
- 选填字段标注 (optional)，必填字段不标注星号（默认所有字段必填，选填才需特别说明）

### 4.2 按钮交互
- 主按钮（Pay now、Save、Apply）使用品牌色填充，悬停时加深
- 次按钮（Not now）使用描边样式，与主按钮形成视觉层级
- 按钮点击后应有加载状态（loading），防止重复提交

### 4.3 单选/复选交互
- 单选组：点击整个卡片区域即可选中，不限于点击单选按钮本身
- 复选框：独立勾选，不影响其他选项
- 选中状态有明确的视觉反馈（边框变色、背景色变化）

### 4.4 展开/收起交互
- 可展开区域（新增地址、账单地址）使用平滑过渡动画
- 展开后按钮文字或图标相应变化，提示可收起

### 4.5 响应式
- PC 端：左右双栏布局（70% / 30%）
- 移动端（≤900px）：单栏布局，订单摘要移至表单下方或可折叠

---

## 五、异常与提醒汇总

| 异常场景 | 触发时机 | 提醒方式 | 用户操作 |
|----------|----------|----------|----------|
| 配送选项变更 | 进入结账页时校验 | 黄色警告框 | 重新确认配送方式 |
| 邮箱为空/格式错 | 点击 Pay now / 失焦 | 输入框下方提示 + 弹窗 | 修正邮箱 |
| 地址必填项为空 | 提交时 | 输入框标红 + 提示 | 补全地址 |
| 折扣码无效 | 点击 Apply | 弹窗提示 | 重新输入或移除 |
| 卡号校验失败 | 失焦/提交 | 输入框下方提示 | 修正卡号 |
| 信用卡过期 | 失焦/提交 | 输入框下方提示 | 更换卡片 |
| 支付处理失败 | 提交支付后 | 错误提示条 | 重试或更换支付方式 |
| 库存不足 | 提交订单时 | 错误提示 | 返回购物车调整 |
| 未登录保存信息 | 点击 Save | 引导登录弹窗 | 登录/注册或取消 |


### 6.4 间距与布局规范（推荐）
- 模块间距：36px
- 表单字段间距：12px
- 卡片内边距：14-16px
- 左栏左右内边距：48px
- 右栏左右内边距：32px
- 双列字段间距：12px

---



*文档结束*
