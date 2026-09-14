import 'package:flutter/foundation.dart';

/// Epoch globale della sessione (F2 Gate C).
///
/// Viene incrementato a ogni transizione di sessione — login, logout, cambio
/// server, sessione scaduta — dal solo `AuthController`. `main.dart` ascolta
/// questo notifier e ricrea il `ProviderScope` radice a ogni bump: la
/// ricreazione dello scope azzera **tutte** le cache dei provider non
/// autoDispose (dashboard, portfolio, watchlist, impostazioni, ...), evitando
/// che dopo un cambio di server o di utente restino visibili dati del backend
/// o dell'utente precedente.
///
/// Il valore non è significativo di per sé: conta il numero di bump, usato
/// come chiave del nuovo scope.
final ValueNotifier<int> sessionEpoch = ValueNotifier<int>(0);

/// Incrementa [sessionEpoch] e notifica i listener.
///
/// Da chiamare esclusivamente nelle transizioni di sessione di
/// `AuthController` (login riuscito, logout, cambio server, sessione
/// scaduta), **mai** in `build()`: il bootstrap iniziale non deve ricreare lo
/// scope né ripetere il bootstrap stesso.
void bumpSessionEpoch() {
  sessionEpoch.value++;
}

/// True quando una richiesta autenticata ha ricevuto 401 (sessione scaduta).
///
/// Segnale fuori dallo scope, come [sessionEpoch]: sopravvive alla
/// ricreazione del `ProviderScope`, così il nuovo `AuthController.build()` può
/// inizializzare `AuthState.sessionExpired` e il router porta a
/// `/login?expired=1` (l'alert "Sessione non valida o scaduta" non va perso).
/// Il bootstrap consuma il segnale riportandolo a `false` dopo la lettura.
final ValueNotifier<bool> sessionExpiredFlag = ValueNotifier<bool>(false);

/// Messaggio informativo una tantum da mostrare sulla schermata di login
/// (es. dopo un cambio server). Sopravvive alla ricreazione dello scope; la
/// `LoginScreen` lo consuma al primo build riportandolo a `null`.
final ValueNotifier<String?> sessionNotice = ValueNotifier<String?>(null);

/// Copy della notice impostata da `AuthController.changeServer`.
const String kServerChangedNotice = 'Server aggiornato. Effettua il login.';

/// Azzera [sessionExpiredFlag] e [sessionNotice].
///
/// Chiamata dal login riuscito: dopo un accesso valido non c'è alcun avviso
/// pendente da mostrare.
void clearSessionSignals() {
  sessionExpiredFlag.value = false;
  sessionNotice.value = null;
}
