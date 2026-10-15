# 菜单栏图标

`Source.png` 是用户提供的三个状态的透明参考图，保留供后续调整，不随 App 打包。

`StatusBarNormalTemplate`、`StatusBarSpeakingTemplate`、`StatusBarMouseTemplate` 分别对应普通、语音中和鼠标模式。图片从参考图裁切，白色图形转为纯黑的透明模板，内部黑色区域转为透明；没有背景或状态文字。保留抗锯齿 Alpha 通道，图形等比居中放入 18 × 18 pt 画布。

每个状态提供 18 × 18 px 的普通 PNG 和 36 × 36 px 的 `@2x` PNG。构建时复制到 App 资源目录，由 `StatusBarIcon` 按名称加载并设置 `isTemplate`，让 AppKit 适配菜单栏的深浅背景和高亮状态。三个状态占用同样宽度，语音状态优先于鼠标模式；原状态文字用于悬停提示和辅助功能标签。
