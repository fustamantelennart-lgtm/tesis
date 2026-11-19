import 'domain.dart';

class ContextoRevision {
  const ContextoRevision(this.casoId, this.revisionId, this.cultivo);
  final String casoId;
  final String revisionId;
  final Cultivo cultivo;
}

/// Owns the immutable case/revision/crop tuple while an image is selected.
class ControlFlujo {
  ControlFlujo({Cultivo inicial = Cultivo.cana}) : cultivo = inicial;
  Cultivo cultivo;
  ContextoRevision? revision;
  bool ocupado = false;
  String? destinoPendiente;

  bool cambiarCultivo(Cultivo nuevo) {
    if (ocupado || revision != null) return false;
    cultivo = nuevo;
    return true;
  }

  bool seleccionarRevision(ContextoRevision contexto) {
    if (ocupado) return false;
    revision = contexto;
    cultivo = contexto.cultivo;
    return true;
  }

  bool iniciar() {
    if (ocupado) return false;
    ocupado = true;
    return true;
  }

  void finalizar() { ocupado = false; }
  void confirmar() { revision = null; }
  bool cancelarRevision() {
    if (ocupado) return false;
    revision = null;
    return true;
  }

  String? abrirDestino(String destino) {
    if (ocupado || revision != null) { destinoPendiente = destino; return null; }
    return destino;
  }

  String? consumirDestino() {
    if (ocupado || revision != null) return null;
    final destino = destinoPendiente;
    destinoPendiente = null;
    return destino;
  }
}
