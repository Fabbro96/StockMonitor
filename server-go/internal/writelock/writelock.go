// Package writelock serializza le mutazioni per-utente in-process,
// mirror di _get_user_lock in backend/routers/portfolio.py (deployment a
// singolo processo). Il vincolo DB resta la difesa di ultima istanza.
package writelock

import "sync"

var locks sync.Map // int64 -> *sync.Mutex

// For ritorna (creandolo se serve) il lock di scrittura dell'utente.
func For(userID int64) *sync.Mutex {
	if v, ok := locks.Load(userID); ok {
		return v.(*sync.Mutex)
	}
	mu := &sync.Mutex{}
	actual, _ := locks.LoadOrStore(userID, mu)
	return actual.(*sync.Mutex)
}
