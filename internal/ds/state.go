package ds

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
)

// State is the managed selection and file ownership of one target.
type State struct {
	Schema    int                  `json:"schema"`
	Selection Selection            `json:"selection"`
	Owned     map[string]Ownership `json:"owned"`
}

// Ownership records what ds last wrote at a path.
type Ownership struct {
	Kind   string `json:"kind"`
	Source string `json:"source,omitempty"`
	SHA256 string `json:"sha256,omitempty"`
}

// Ownership kinds.
const (
	ownLink  = "link"
	ownFile  = "file"
	ownBlock = "block"
)

const stateSchema = 1

// LoadState reads a target's state; a missing file is an empty state.
func LoadState(t Target) (State, error) {
	s := State{Schema: stateSchema, Owned: map[string]Ownership{}}
	data, err := os.ReadFile(statePath(t))
	if errors.Is(err, fs.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return s, err
	}
	if err := json.Unmarshal(data, &s); err != nil {
		return s, fmt.Errorf("decode %s: %w", statePath(t), err)
	}
	if s.Schema != stateSchema {
		return s, fmt.Errorf("unsupported state schema %d in %s", s.Schema, statePath(t))
	}
	if s.Owned == nil {
		s.Owned = map[string]Ownership{}
	}
	return s, nil
}

// SaveState writes state atomically.
func SaveState(t Target, s State) error {
	s.Schema = stateSchema
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return writeAtomic(statePath(t), append(data, '\n'), 0o644)
}

// writeAtomic replaces a file through a same-directory rename.
func writeAtomic(p string, data []byte, mode fs.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(p), "."+filepath.Base(p)+".*")
	if err != nil {
		return err
	}
	_, werr := tmp.Write(data)
	cerr := tmp.Close()
	if err := errors.Join(werr, cerr, os.Chmod(tmp.Name(), mode)); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	if err := os.Rename(tmp.Name(), p); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	return nil
}

// Lock is an advisory lock on a target, released at process exit.
type Lock struct{ f *os.File }

// LockFDEnv passes an inherited lock descriptor to a candidate ds.
const LockFDEnv = "DS_LOCK_FD"

// AcquireLock takes the target lock without waiting.
func AcquireLock(t Target) (*Lock, error) {
	p := lockPath(t)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(p, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, fmt.Errorf("another ds operation holds %s", p)
		}
		return nil, fmt.Errorf("lock %s: %w", p, err)
	}
	return &Lock{f: f}, nil
}

// InheritedLock adopts a lock descriptor handed over by a parent ds.
func InheritedLock(getenv Getenv) (*Lock, bool) {
	v := getenv(LockFDEnv)
	if v == "" {
		return nil, false
	}
	fd, err := strconv.Atoi(v)
	if err != nil || fd < 3 {
		return nil, false
	}
	return &Lock{f: os.NewFile(uintptr(fd), "ds-lock")}, true
}

// File exposes the descriptor for handoff to a child process.
func (l *Lock) File() *os.File { return l.f }

// Close drops the lock.
func (l *Lock) Close() error { return l.f.Close() }
