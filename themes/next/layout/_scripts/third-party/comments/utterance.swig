{% if theme.utteranc and theme.utteranc.enable %}

  <div>
      <style>
        .utterances-frame{min-width: 122%; left: 36px}
      </Style>
      <script src="{{ theme.utteranc.cdn }}"
            repo="{{ theme.utteranc.repo }}"
            issue-term="{{ theme.utteranc.issue-term }}"
            theme="{{ theme.utteranc.theme }}"
            label="{{ theme.utteranc.label }}"
            crossorigin="anonymous"
            async>
      </script>
  </div>

{% endif %}