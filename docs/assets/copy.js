// Adds a "Copy" button to every .codeblock. No dependencies.
document.querySelectorAll('.codeblock').forEach(function (block) {
  var pre = block.querySelector('pre');
  if (!pre) return;
  var btn = document.createElement('button');
  btn.className = 'copy-btn';
  btn.type = 'button';
  btn.textContent = 'Copy';
  btn.setAttribute('aria-label', 'Copy code to clipboard');
  btn.addEventListener('click', function () {
    var text = pre.innerText.replace(/\n$/, '');
    navigator.clipboard.writeText(text).then(function () {
      btn.textContent = 'Copied';
      btn.classList.add('copied');
      setTimeout(function () { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 1600);
    });
  });
  block.appendChild(btn);
});
