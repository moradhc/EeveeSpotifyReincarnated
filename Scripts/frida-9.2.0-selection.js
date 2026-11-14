// Load as a file (-l); do not paste this multiline script into the Frida REPL.
// Repeats the confirmed scoped change for 120 seconds; observes other callers.
(function () {
    if (globalThis.eeveeSelectionProbe) throw Error('Sonda ya activa');
    if (globalThis.eeveeLicenseTest) throw Error('Espera a FIN de la prueba anterior');
    var m = Process.mainModule, p = m.base.add(32), uuid = '';
    for (var i = 0, n = m.base.add(16).readU32(); i < n; i++) {
        var cmd = p.readU32(), size = p.add(4).readU32();
        if (size < 8) throw Error('Cabecera invalida');
        if (cmd === 27) {
            uuid = Array.from(new Uint8Array(p.add(8).readByteArray(16)))
                .map(function (x) { return x.toString(16).padStart(2, '0'); }).join('');
            break;
        }
        p = p.add(size);
    }
    if (uuid !== 'b49e75781d8635d38bb57daf68fed8a8') throw Error('UUID no compatible');
    function hex(p) {
        return Array.from(new Uint8Array(p.readByteArray(8)))
            .map(function (x) { return x.toString(16).padStart(2, '0'); }).join('');
    }
    var target = m.base.add(0x5db6994), builder = m.base.add(0x39d5bb8);
    if (hex(target) !== '00300091c0035fd6' || hex(builder) !== '080040b91f150071')
        throw Error('Codigo distinto o hook ya instalado: reinicia Spotify sin V11/otras sondas');
    function label(a) {
        a = a.strip();
        return a.compare(m.base) >= 0 && a.compare(m.base.add(m.size)) < 0
            ? 'Spotify+' + a.sub(m.base) : 'otro-modulo';
    }
    var value = Memory.alloc(4); value.writeU32(0);
    var observed = {}, distinct = 0, hits = 0, total = 0, phase = 'reposo';
    globalThis.eeveeSelectionMark = function () {
        phase = 'seleccion';
        observed = {}; distinct = 0;
        console.log('[SELECT] MARCA: toca ahora una cancion concreta');
    };
    var h = Interceptor.attach(target, {
        onEnter: function () {
            total++;
            this.isBuilder = this.returnAddress.strip().equals(builder);
            this.event = null;
            var caller = label(this.returnAddress);
            if (!this.isBuilder && distinct < 16 && !observed[caller]) {
                observed[caller] = true; distinct++;
                this.event = {phase: phase, caller: caller};
                try {
                    this.event.trace = Thread.backtrace(this.context, Backtracer.ACCURATE)
                        .slice(0, 10).map(label);
                } catch (_) { this.event.trace = ['no-disponible']; }
            }
        },
        onLeave: function (r) {
            try {
                var state = r.readU32();
                if (this.event) {
                    this.event.state = state;
                    console.log('[SELECT] ' + JSON.stringify(this.event));
                }
                if (this.isBuilder && (state === 3 || state === 4)) {
                    r.replace(value);
                    if (++hits <= 3) console.log('[SELECT] CORE aplicado ' + state + ' -> 0');
                }
            } catch (e) { console.log('[SELECT] ERROR ' + e); }
        }
    });
    globalThis.eeveeSelectionProbe = {hook: h, value: value};
    setTimeout(function () {
        h.detach();
        delete globalThis.eeveeSelectionProbe;
        delete globalThis.eeveeSelectionMark;
        console.log('[SELECT] FIN ' + JSON.stringify({lecturas: total, cambiosCore: hits, otrosSitiosUltimaFase: distinct}));
    }, 120000);
    console.log('[SELECT] READY 120 segundos; escribe eeveeSelectionMark() antes de tocar la cancion');
})();
