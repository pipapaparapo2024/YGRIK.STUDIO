(function () {
  var DESIGN_WIDTH = 1619;
  var MIN_SCALE_WIDTH = 1025;
  var scheduled = null;

  function apply() {
    var vp = document.getElementById('scaleViewport');
    var fr = document.getElementById('scaleFrame');
    if (!vp || !fr) return;
    var w = window.innerWidth;

    if (w >= MIN_SCALE_WIDTH) {
      var scale = w / DESIGN_WIDTH;
      var transform = 'scale(' + scale + ')';
      if (fr.style.transform !== transform) fr.style.transform = transform;
      var height = Math.ceil(fr.offsetHeight * scale) + 'px';
      if (vp.style.height !== height) vp.style.height = height;
    } else {
      if (fr.style.transform !== '') fr.style.transform = '';
      if (vp.style.height !== '') vp.style.height = '';
    }
  }

  function scheduleApply() {
    clearTimeout(scheduled);
    scheduled = setTimeout(apply, 30);
  }

  window.addEventListener('resize', scheduleApply);
  window.addEventListener('orientationchange', scheduleApply);
  window.addEventListener('load', apply);
  document.addEventListener('DOMContentLoaded', apply);
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(apply);
  }
  setTimeout(apply, 50);
  setTimeout(apply, 500);
  apply();
})();
