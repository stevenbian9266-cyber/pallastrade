// PALLAS-CUSTOM: 侧边栏滚动位置保持（Bug 修复 2026-08-18）
//
// #main-sidebar 是 fixed + overflow-y-auto 的独立滚动容器。Turbo Drive
// 页面导航会替换 DOM，但只恢复 window 滚动位置，不会恢复固定容器的
// scrollTop → 点击底部导航项后滚动位置回到顶部。
//
// 方案：turbo:before-render 保存 .sidebar-content 的 scrollTop，
// turbo:render 后恢复（requestAnimationFrame 确保新 DOM 已布局）。
const SIDEBAR_SCROLL_KEY = 'pallastrade_admin_sidebar_scroll';

export function initSidebarScrollRestore() {
  let savedScrollTop = 0;

  document.addEventListener('turbo:before-render', () => {
    const content = document.querySelector('#main-sidebar .sidebar-content');
    if (content) {
      savedScrollTop = content.scrollTop;
    }
  });

  document.addEventListener('turbo:render', () => {
    const content = document.querySelector('#main-sidebar .sidebar-content');
    if (content && savedScrollTop > 0) {
      // 新 DOM 布局后恢复；用两层 rAF 确保高度已计算（折叠/展开状态一致时直接恢复）。
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          content.scrollTop = savedScrollTop;
        });
      });
    }
  });
}
