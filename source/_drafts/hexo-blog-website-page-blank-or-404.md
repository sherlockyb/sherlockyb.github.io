---
title: hexo博客网站主页空白或404
tags:
  - hexo
categories:
  - Tool
date: 2022-03-24 22:00:00
---

太久没更新博客了，最近准备拾起来。于是为了“改头换面”，今天想调整一下 sidebar 上的头像，因为是新电脑，没有 hexo 等环境，于是按照之前分享过的一篇[博文](https://www.yangbing.club/2019/06/29/save-hexo-source-post-with-git-branch/)，安装 hexo，替换 source 目录下的头像图片并调整 _config.xml，本地预览一切正常，然后直接执行 `hexo d`部署完成，访问网站域名 www.yangbing.club 发现直接404了，刷新了多次，用无痕浏览，等了许久再试，还是老样子，这可把我吓坏了，从未遇到过这等情况，等于博客直接挂了。

<!--more-->

# 开始排查

## github上的线索

发现 Actions 中此次 deploy 触发的 build 和 deploy 均失败了。

### build error如下，[detail](https://github.com/sherlockyb/sherlockyb.github.io/runs/5642002288?check_suite_focus=true)

```shell
/usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/theme.rb:84:in `rescue in gemspec': The hexo-theme-next theme could not be found. (Jekyll::Errors::MissingDependencyException)
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/theme.rb:81:in `gemspec'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/theme.rb:19:in `root'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/theme.rb:12:in `initialize'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/site.rb:439:in `new'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/site.rb:439:in `configure_theme'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/site.rb:55:in `config='
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/site.rb:23:in `initialize'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/commands/build.rb:30:in `new'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/commands/build.rb:30:in `process'
	from /usr/local/bundle/gems/github-pages-225/bin/github-pages:70:in `block (3 levels) in <top (required)>'
	from /usr/local/bundle/gems/mercenary-0.3.6/lib/mercenary/command.rb:220:in `block in execute'
	from /usr/local/bundle/gems/mercenary-0.3.6/lib/mercenary/command.rb:220:in `each'
	from /usr/local/bundle/gems/mercenary-0.3.6/lib/mercenary/command.rb:220:in `execute'
	from /usr/local/bundle/gems/mercenary-0.3.6/lib/mercenary/program.rb:42:in `go'
	from /usr/local/bundle/gems/mercenary-0.3.6/lib/mercenary.rb:19:in `program'
	from /usr/local/bundle/gems/github-pages-225/bin/github-pages:6:in `<top (required)>'
	from /usr/local/bundle/bin/github-pages:23:in `load'
	from /usr/local/bundle/bin/github-pages:23:in `<main>'
/usr/local/lib/ruby/2.7.0/rubygems/dependency.rb:311:in `to_specs': Could not find 'hexo-theme-next' (>= 0) among 158 total gem(s) (Gem::MissingSpecError)
Checked in 'GEM_PATH=/github/home/.gem/ruby/2.7.0:/usr/local/lib/ruby/gems/2.7.0:/usr/local/bundle', execute `gem env` for more information
	from /usr/local/lib/ruby/2.7.0/rubygems/dependency.rb:323:in `to_spec'
	from /usr/local/lib/ruby/2.7.0/rubygems/specification.rb:986:in `find_by_name'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/theme.rb:82:in `gemspec'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/theme.rb:19:in `root'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/theme.rb:12:in `initialize'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/site.rb:439:in `new'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/site.rb:439:in `configure_theme'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/site.rb:55:in `config='
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/site.rb:23:in `initialize'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/commands/build.rb:30:in `new'
	from /usr/local/bundle/gems/jekyll-3.9.0/lib/jekyll/commands/build.rb:30:in `process'
	from /usr/local/bundle/gems/github-pages-225/bin/github-pages:70:in `block (3 levels) in <top (required)>'
	from /usr/local/bundle/gems/mercenary-0.3.6/lib/mercenary/command.rb:220:in `block in execute'
	from /usr/local/bundle/gems/mercenary-0.3.6/lib/mercenary/command.rb:220:in `each'
	from /usr/local/bundle/gems/mercenary-0.3.6/lib/mercenary/command.rb:220:in `execute'
	from /usr/local/bundle/gems/mercenary-0.3.6/lib/mercenary/program.rb:42:in `go'
	from /usr/local/bundle/gems/mercenary-0.3.6/lib/mercenary.rb:19:in `program'
	from /usr/local/bundle/gems/github-pages-225/bin/github-pages:6:in `<top (required)>'
	from /usr/local/bundle/bin/github-pages:23:in `load'
	from /usr/local/bundle/bin/github-pages:23:in `<main>'
  Logging at level: debug
Configuration file: /github/workspace/./_config.yml
             Theme: hexo-theme-next
github-pages 225 | Error:  The hexo-theme-next theme could not be found.
```

### deploy error 如下，[detail](https://github.com/sherlockyb/sherlockyb.github.io/runs/5642009024?check_suite_focus=true)

```
Actor: sherlockyb
Action ID: 2021541511
Artifact URL: https://pipelines.actions.githubusercontent.com/QrvX2bmakfCgkbXyG4yo3O1Y8LmS1Eviu5tBLZPSm6baFeu9Sw/_apis/pipelines/workflows/2021541511/artifacts?api-version=6.0-preview
{"count":0,"value":[]}
Failed to create deployment for 64e432b334b99462a8b0c082f955d6f5a99e6cde.
Error: Error: No uploaded artifact was found! Please check if there are any errors at build step.
Error: Error: No uploaded artifact was found! Please check if there are any errors at build step.
Sending telemetry for run id 2021541511
```



可能是CNAME失效，导致域名跳转失败？

直接访问 https://sherlockyb.github.io 试试，发现并没有出现404，但首页空白，难道 hexo 生成的 index.html 是空的？



