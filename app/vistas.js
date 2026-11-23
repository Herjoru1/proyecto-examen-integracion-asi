const moneda = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' });
const entero = new Intl.NumberFormat('es-MX');
const entidades = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
const escapar = (valor) => String(valor).replace(/[&<>"']/g, (caracter) => entidades[caracter]);

function pagina(titulo, contenido, usuario = null, activa = '') {
    const menu = usuario ? `
        <nav aria-label="Menú principal">
            <a href="/articulos"${activa === 'articulos' ? ' aria-current="page"' : ''}>Artículos</a>
            ${usuario.rol === 'administrador' ? `
                <a href="/existencias"${activa === 'existencias' ? ' aria-current="page"' : ''}>Existencias</a>` : ''}
        </nav>
        <div class="cuenta">
            <span>${escapar(usuario.usuario)} · ${escapar(usuario.etiqueta)}</span>
            <form action="/salir" method="post"><button class="secundario">Cerrar sesión</button></form>
        </div>` : '';

    return `<!doctype html>
<html lang="es-MX">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapar(titulo)} · Inventario ASI</title>
    <link rel="stylesheet" href="/estilos.css">
</head>
<body>
    <header class="topbar"><div class="shell cabecera">
        <strong>Inventario ASI</strong>${menu}
    </div></header>
    <main class="shell">${contenido}</main>
</body>
</html>`;
}

export function acceso(error = '') {
    return pagina('Iniciar sesión', `
        <section class="panel acceso" aria-labelledby="titulo">
            <h1 id="titulo">Iniciar sesión</h1>
            ${error ? `<p class="notice error" role="alert">${escapar(error)}</p>` : ''}
            <form action="/sesion" method="post">
                <label>Usuario<input name="usuario" autocomplete="username" required maxlength="64"></label>
                <label>Contraseña<input name="password" type="password" autocomplete="current-password" required maxlength="128"></label>
                <button class="primary">Entrar</button>
            </form>
        </section>`);
}

export function articulos(usuario, filas) {
    const cuerpo = filas.map((fila) => `<tr>
        <td class="number">${escapar(fila.id_articulo)}</td>
        <th scope="row">${escapar(fila.nombre)}</th>
        <td class="number">${moneda.format(fila.precio)}</td>
        <td class="number${fila.elementos_existentes === 0 ? ' out-of-stock' : ''}">${entero.format(fila.elementos_existentes)}</td>
    </tr>`).join('');
    return pagina('Artículos', `
        <div class="page-heading"><h1>Artículos</h1><p>${entero.format(filas.length)} artículos registrados</p></div>
        <div class="panel table-scroll">
            <table aria-label="Inventario de artículos">
                <thead><tr>
                    <th scope="col">ID</th><th scope="col">Nombre</th>
                    <th scope="col">Precio (MXN)</th><th scope="col">Elementos existentes</th>
                </tr></thead>
                <tbody>${cuerpo || '<tr><td colspan="4" class="empty">No hay artículos registrados.</td></tr>'}</tbody>
            </table>
        </div>`, usuario, 'articulos');
}

export function existencias(usuario, totales) {
    return pagina('Existencias', `
        <div class="page-heading"><h1>Existencias</h1></div>
        <dl class="resumen">
            <div class="panel"><dt>Artículos registrados</dt><dd>${entero.format(totales.articulos)}</dd></div>
            <div class="panel"><dt>Unidades en inventario</dt><dd>${entero.format(totales.unidades)}</dd></div>
            <div class="panel"><dt>Artículos agotados</dt><dd>${entero.format(totales.agotados)}</dd></div>
        </dl>`, usuario, 'existencias');
}

export function mensaje(titulo, detalle, usuario = null) {
    return pagina(titulo, `<section class="panel acceso"><h1>${escapar(titulo)}</h1>
        <p>${escapar(detalle)}</p><a href="/">Volver al inicio</a></section>`, usuario);
}
