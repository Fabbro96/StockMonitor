// Package web espone la build web embedded (server-go/web/dist, creata da
// fix-2) via embed.FS.
//
// Nota: //go:embed accetta solo path relativi alla directory del sorgente
// (niente `..`), quindi l'embed vive qui dentro server-go/web/ come
// `dist` e cmd/stockmon/main.go lo importa. Nessun contenuto di dist/
// viene modificato.
package web

import "embed"

// Dist contiene la build web statica (index.html, app.js, style.css).
//
//go:embed dist
var Dist embed.FS
