// ES5 a propósito: el iPad Air 1 se queda en iOS 12.
// Cada toque pide un reto de un solo uso y lo firma con la clave (HMAC-SHA256);
// la clave se guarda en el iPad y nunca se envía por la red.
(function () {
  var estado = document.getElementById('estado');
  var pantalla = document.getElementById('clavePantalla');
  var input = document.getElementById('claveInput');

  function normalizar(c) { return (c || '').replace(/[\s-]/g, '').toUpperCase(); }
  function leerClave() { try { return localStorage.getItem('clave') || ''; } catch (e) { return window._clave || ''; } }
  function guardarClave(c) { window._clave = c; try { localStorage.setItem('clave', c); } catch (e) {} }

  function mostrar(texto, aviso) {
    estado.textContent = texto;
    estado.className = aviso ? 'aviso' : '';
  }

  function pedirClave() { input.value = ''; pantalla.style.display = 'flex'; input.focus(); }

  function pedir(metodo, url, cabeceras, listo) {
    var xhr = new XMLHttpRequest();
    xhr.open(metodo, url);
    for (var k in cabeceras) if (cabeceras.hasOwnProperty(k)) xhr.setRequestHeader(k, cabeceras[k]);
    xhr.timeout = 15000;
    xhr.onload = function () {
      var datos = {};
      try { datos = JSON.parse(xhr.responseText); } catch (e) {}
      listo(xhr.status, datos);
    };
    xhr.onerror = xhr.ontimeout = function () { listo(0, {}); };
    xhr.send();
  }

  function firmar(accion, listo) {
    pedir('GET', '/reto', {}, function (status, datos) {
      if (status !== 200) return listo(status, datos);
      var firma = Firma.hmac(leerClave(), datos.reto + ':' + accion);
      pedir('POST', '/accion/' + accion, { 'X-Reto': datos.reto, 'X-Firma': firma }, listo);
    });
  }

  function comprobarEstado() {
    if (!leerClave()) return pedirClave();
    firmar('estado', function (status, datos) {
      if (status === 401) { mostrar('Clave incorrecta', true); return pedirClave(); }
      if (status === 0) return mostrar('Sin conexión con la Mac', true);
      if (status !== 200) return mostrar(datos.error || 'Error', true);
      if (datos.accesibilidad) mostrar('Listo · ' + (datos.nombre || ''));
      else mostrar('⚠️ Falta permiso de Accesibilidad en la Mac', true);
    });
  }

  function quitarClase(el, c) { el.className = el.className.replace(' ' + c, ''); }

  function ejecutar(boton) {
    var accion = boton.getAttribute('data-accion');
    boton.className += ' pulsado';
    firmar(accion, function (status, datos) {
      quitarClase(boton, 'pulsado');
      if (status === 200) return mostrar('✓ ' + boton.textContent.replace(/^\S+\s*/, ''));
      mostrar(status === 0 ? 'Sin conexión con la Mac' : (datos.error || 'Error'), true);
      boton.className += ' error';
      setTimeout(function () { quitarClase(boton, 'error'); }, 600);
      if (status === 401) pedirClave();
    });
  }

  document.getElementById('claveGuardar').onclick = function () {
    guardarClave(normalizar(input.value));
    pantalla.style.display = 'none';
    comprobarEstado();
  };
  document.getElementById('cambiarClave').onclick = pedirClave;

  var botones = document.querySelectorAll('.btn');
  for (var i = 0; i < botones.length; i++) {
    botones[i].onclick = function () { ejecutar(this); };
  }

  // Emparejar con el código QR de la app de la Mac: la clave llega en el
  // fragmento (#clave=...), que el navegador nunca envía al servidor.
  var m = /[#&]clave=([A-Za-z0-9-]+)/.exec(location.hash);
  if (m) {
    guardarClave(normalizar(m[1]));
    try { history.replaceState(null, '', location.pathname); } catch (e) { location.hash = ''; }
  }

  comprobarEstado();
  // Latido: la app de la Mac muestra el dispositivo como conectado mientras llegue.
  setInterval(function () { if (leerClave() && pantalla.style.display !== 'flex') comprobarEstado(); }, 20000);
})();
