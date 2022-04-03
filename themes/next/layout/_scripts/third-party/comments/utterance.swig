{% if theme.utteranc and theme.utteranc.enable %}

  <script type="text/javascript">
    var div = document.createElement('div');
    div.id = 'utteranc-comments';

    var styleEle = document.createElement('style');
    styleEle.innerHTML = '.utterances-frame{min-width: 102%; left: -5px}';
    div.appendChild(styleEle);

    var scriptEle = document.createElement('script');
    scriptEle.src = '{{ theme.utteranc.cdn }}';
    scriptEle.setAttribute('repo', '{{ theme.utteranc.repo }}');
    scriptEle.setAttribute('issue-term', '{{ theme.utteranc['issue-term'] }}');
    scriptEle.setAttribute('theme', '{{ theme.utteranc.theme }}');
    scriptEle.setAttribute('label', '{{ theme.utteranc.label }}');
    scriptEle.setAttribute('async', !0);
    div.appendChild(scriptEle);

    var container = document.getElementById('utteranc-container');
    if (container) {
      container.appendChild(div);
    }
  </script>

{% endif %}