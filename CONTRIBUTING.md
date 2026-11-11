# 为 Dòng 做贡献

欢迎来到 Dòng。既然你点开了这个文件，说明你想让这个项目变得更好 —— 那我们就直入正题。

有任何问题，可以[开 issue](https://github.com/zhang-1-kael/dong/issues) 或参与讨论。

## 你能帮上什么

1. **报 bug** —— 去 Issues 页面，会有人引导你该提供哪些信息。
2. **提想法** —— 先开个 issue 说清楚要解决什么问题，被采纳后再动手，避免白做。
3. **改代码** —— 修 bug、补功能、优化转码算法，都欢迎。
4. **改文档** —— 错别字、说不清的地方、缺失的坑记录，同样重要。

## 从想法到合并

### 第一步：先开 issue

在动手之前，先创建一个 issue，把你想改的东西说清楚。
这能避免你的工作和正在进行的改动撞车。等作者回复「可以」之后，再开始写代码。

### 第二步：Fork 仓库

在仓库页面右上角点 **Fork**，把 Dòng 复制到你自己的账号下。

### 第三步：克隆你的 fork

```bash
git clone https://github.com/<你的用户名>/dong.git
cd dong
git checkout -b 我的改动
```

### 第四步：改代码

- 代码风格遵循仓库里的 [`.swiftformat`](.swiftformat)，提交前跑一遍：
  ```bash
  swiftformat .
  ```
- 编译必须通过：
  ```bash
  ./build.sh
  ```
- 界面相关改动请附上前后的截图。
- commit message 用简洁的中文或英文说明「做了什么、为什么」。

### 第五步：提 Pull Request

```bash
git add .
git commit -m "fix: 修了什么"
git push origin 我的改动
```

然后回你 fork 的页面，点 **Compare & pull request**。

## AI 使用政策

本项目接受 AI 辅助开发，但请在 PR 模板里如实说明使用程度。
如果你计划在贡献中使用 AI，请先读一遍 [AI 使用政策](AI_POLICY.md)。

## 行为准则

参与本项目即表示你同意遵守[行为准则](CODE_OF_CONDUCT.md)。
