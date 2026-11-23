import { createHash, randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { promisify } from 'node:util';
import express from 'express';
import pg from 'pg';
import * as vistas from './vistas.js';

const app = express();
const pool = new pg.Pool({ max: 16, connectionTimeoutMillis: 3000, statement_timeout: 5000 });
const derivar = promisify(scrypt);
const cookie = '__Host-asi_sesion';
const duracionSesion = 8 * 60 * 60 * 1000;
const origen = 'https://proyecto.final.asi';

pool.on('error', (error) => console.error('Conexión inactiva de PostgreSQL:', error.message));
app.disable('x-powered-by');
app.use(express.urlencoded({ extended: false, limit: '4kb', parameterLimit: 8 }));
app.use((req, res, next) => {
    res.set('Cache-Control', 'no-store');
    if (req.method === 'POST' && req.get('Origin') !== origen) {
        return res.status(403).send(vistas.mensaje('Solicitud rechazada', 'Origen de formulario inválido.'));
    }
    next();
});

function tokenDe(req) {
    const valor = req.headers.cookie?.match(/(?:^|;\s*)__Host-asi_sesion=([0-9a-f]{64})(?:;|$)/)?.[1];
    return valor ? createHash('sha256').update(valor).digest('hex') : null;
}

async function usuarioDe(req) {
    const token = tokenDe(req);
    if (!token) return null;
    const resultado = await pool.query(`
        SELECT u.id, u.usuario, r.codigo AS rol, r.etiqueta
        FROM sesiones s JOIN usuarios u ON u.id = s.usuario_id JOIN roles r ON r.codigo = u.rol
        WHERE s.token_hash = $1 AND s.vence > now()`, [token]);
    return resultado.rows[0] || null;
}

const opcionesCookie = { httpOnly: true, secure: true, sameSite: 'strict', path: '/' };

function medir(nombre, controlador) {
    return async (req, res) => {
        if (req.get('X-ASI-Perfil') !== '1') return controlador(req, res);
        const rssInicial = process.memoryUsage.rss();
        let rssMax = rssInicial;
        const reloj = performance.now();
        const cpu = process.cpuUsage();
        const muestreo = setInterval(() => {
            rssMax = Math.max(rssMax, process.memoryUsage.rss());
        }, 5);
        try {
            return await controlador(req, res);
        } finally {
            clearInterval(muestreo);
            const transcurrido = performance.now() - reloj;
            const usado = process.cpuUsage(cpu);
            const rssFinal = process.memoryUsage.rss();
            console.log(JSON.stringify({
                tipo: 'perfil', script: nombre,
                tiempo_ms: transcurrido, cpu_ms: (usado.user + usado.system) / 1000,
                rss_inicial_bytes: rssInicial, rss_final_bytes: rssFinal,
                rss_max_bytes: Math.max(rssMax, rssFinal),
            }));
        }
    };
}

app.get('/salud', medir('comprobar_salud', async (req, res) => {
    await pool.query('SELECT 1');
    res.type('text').send('ok');
}));

app.get('/', medir('inicio', async (req, res) => {
    if (await usuarioDe(req)) return res.redirect('/articulos');
    res.send(vistas.acceso());
}));

app.post('/sesion', medir('iniciar_sesion', async (req, res) => {
    const usuario = req.body?.usuario;
    const password = req.body?.password;
    if (typeof usuario !== 'string' || typeof password !== 'string' ||
        !usuario.trim() || usuario.length > 64 || !password || password.length > 128) {
        return res.status(400).send(vistas.acceso('Escribe tu usuario y contraseña.'));
    }

    const resultado = await pool.query(
        'SELECT id, password_hash FROM usuarios WHERE usuario = $1', [usuario.trim()],
    );
    const cuenta = resultado.rows[0];
    const [sal, esperado] = (cuenta?.password_hash || `${'0'.repeat(32)}:${'0'.repeat(128)}`).split(':');
    const recibido = await derivar(password, Buffer.from(sal, 'hex'), 64);
    if (!timingSafeEqual(recibido, Buffer.from(esperado, 'hex')) || !cuenta) {
        return res.status(401).send(vistas.acceso('Usuario o contraseña incorrectos.'));
    }

    const token = randomBytes(32).toString('hex');
    const hash = createHash('sha256').update(token).digest('hex');
    const anterior = tokenDe(req);
    await pool.query(`
        WITH anterior AS (DELETE FROM sesiones WHERE token_hash = $3)
        INSERT INTO sesiones (token_hash, usuario_id, vence) VALUES ($1, $2, now() + interval '8 hours')
    `, [hash, cuenta.id, anterior]);
    res.cookie(cookie, token, { ...opcionesCookie, maxAge: duracionSesion });
    res.redirect(303, '/articulos');
}));

app.get('/articulos', medir('listar_articulos', async (req, res) => {
    const usuario = await usuarioDe(req);
    if (!usuario) return res.redirect('/');
    const resultado = await pool.query(`
        SELECT id_articulo, nombre, precio, elementos_existentes FROM articulos ORDER BY id_articulo`);
    res.send(vistas.articulos(usuario, resultado.rows));
}));

app.get('/existencias', medir('resumen_existencias', async (req, res) => {
    const usuario = await usuarioDe(req);
    if (!usuario) return res.redirect('/');
    if (usuario.rol !== 'administrador') {
        return res.status(403).send(vistas.mensaje('Acceso restringido', 'Tu perfil solo puede consultar artículos.', usuario));
    }
    const resultado = await pool.query(`
        SELECT count(*) AS articulos, coalesce(sum(elementos_existentes), 0) AS unidades,
               count(*) FILTER (WHERE elementos_existentes = 0) AS agotados
        FROM articulos`);
    res.send(vistas.existencias(usuario, resultado.rows[0]));
}));

app.post('/salir', medir('cerrar_sesion', async (req, res) => {
    const token = tokenDe(req);
    if (token) await pool.query('DELETE FROM sesiones WHERE token_hash = $1', [token]);
    res.clearCookie(cookie, opcionesCookie);
    res.redirect(303, '/');
}));

app.use((req, res) => res.status(404).send(vistas.mensaje('Página no encontrada', 'Verifica la dirección.')));
app.use((err, req, res, next) => {
    if (res.headersSent) return next(err);
    if (err.status === 400 || err.status === 413) {
        return res.status(err.status).send(vistas.mensaje('Solicitud inválida', 'Revisa el formulario.'));
    }
    console.error(err);
    res.status(500).send(vistas.mensaje('Error del servidor', 'Intenta nuevamente.'));
});

setInterval(() => {
    pool.query('DELETE FROM sesiones WHERE vence <= now()')
        .catch((error) => console.error('Limpieza de sesiones:', error.message));
}, 15 * 60 * 1000).unref();

app.listen(3000, '0.0.0.0');
