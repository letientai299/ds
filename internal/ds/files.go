package ds

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

// fileState classifies a managed path against its desired content.
type fileState int

const (
	stateMissing fileState = iota
	statePresent
	// stateStale is ds-owned content that can be replaced in place.
	stateStale
	// stateConflict is foreign content; replacing it needs a backup.
	stateConflict
)

func (s fileState) String() string {
	return [...]string{"missing", "present", "outdated", "conflict"}[s]
}

// inspection is the observed state of one managed path.
type inspection struct {
	State  fileState
	Reason string
	// Locked conflicts cannot be resolved with --force.
	Locked bool
}

// managed is desired content at a path: managedLink, managedBlock,
// managedFile, or managedJSON.
type managed interface {
	path() string
	inspect(own map[string]Ownership, roots []string) inspection
	write(replace bool) (Ownership, error)
	describe() string
}

type managedLink struct{ Target, Source string }

type managedBlock struct{ Target, Body string }

type managedFile struct {
	Target  string
	Content []byte
	Mode    fs.FileMode
}

func (m managedLink) path() string  { return m.Target }
func (m managedBlock) path() string { return m.Target }
func (m managedFile) path() string  { return m.Target }

func (m managedLink) describe() string  { return "link " + m.Target + " -> " + m.Source }
func (m managedBlock) describe() string { return "block in " + m.Target }
func (m managedFile) describe() string  { return "file " + m.Target }

func (m managedLink) inspect(own map[string]Ownership, roots []string) inspection {
	info, err := os.Lstat(m.Target)
	if errors.Is(err, fs.ErrNotExist) {
		return inspection{State: stateMissing}
	}
	if err != nil {
		return inspection{State: stateConflict, Reason: err.Error()}
	}
	if info.Mode()&fs.ModeSymlink == 0 {
		return inspection{State: stateConflict, Reason: "existing " + kindOf(info)}
	}
	dest, err := os.Readlink(m.Target)
	if err != nil {
		return inspection{State: stateConflict, Reason: err.Error()}
	}
	if dest == m.Source {
		return inspection{State: statePresent}
	}
	if rec, ok := own[m.Target]; ok && rec.Kind == ownLink && rec.Source == dest {
		return inspection{State: stateStale}
	}
	abs := dest
	if !filepath.IsAbs(abs) {
		abs = filepath.Join(filepath.Dir(m.Target), dest)
	}
	for _, root := range roots {
		if root != "" && within(filepath.Clean(abs), root) {
			return inspection{State: stateStale}
		}
	}
	return inspection{State: stateConflict, Reason: "symlink to " + dest}
}

func (m managedLink) write(replace bool) (Ownership, error) {
	if err := os.MkdirAll(filepath.Dir(m.Target), 0o755); err != nil {
		return Ownership{}, err
	}
	if replace {
		// Replace through a rename so the path never disappears.
		tmp := m.Target + ".ds-new"
		os.Remove(tmp)
		if err := os.Symlink(m.Source, tmp); err != nil {
			return Ownership{}, err
		}
		if err := os.Rename(tmp, m.Target); err != nil {
			os.Remove(tmp)
			return Ownership{}, err
		}
	} else if err := os.Symlink(m.Source, m.Target); err != nil {
		return Ownership{}, err
	}
	return Ownership{Kind: ownLink, Source: m.Source}, nil
}

const (
	blockStart = "# >>> ds managed >>>"
	blockEnd   = "# <<< ds managed <<<"
)

func renderBlock(body string) string {
	return blockStart + "\n" + strings.TrimRight(body, "\n") + "\n" + blockEnd + "\n"
}

// findBlock locates one well-formed block. ok is false when markers are
// unbalanced or repeated.
func findBlock(content string) (start, end int, body string, found, ok bool) {
	first := strings.Index(content, blockStart)
	if first < 0 {
		return 0, 0, "", false, !strings.Contains(content, blockEnd)
	}
	closeAt := strings.Index(content[first:], blockEnd)
	if closeAt < 0 {
		return 0, 0, "", false, false
	}
	closeAt += first
	if strings.Contains(content[first+len(blockStart):closeAt], blockStart) ||
		strings.Contains(content[closeAt+len(blockEnd):], blockStart) ||
		strings.Contains(content[closeAt+len(blockEnd):], blockEnd) ||
		strings.Contains(content[:first], blockEnd) {
		return 0, 0, "", false, false
	}
	end = closeAt + len(blockEnd)
	if end < len(content) && content[end] == '\n' {
		end++
	}
	inner := strings.TrimPrefix(content[first+len(blockStart):closeAt], "\n")
	return first, end, strings.TrimRight(inner, "\n"), true, true
}

func (m managedBlock) inspect(map[string]Ownership, []string) inspection {
	info, err := os.Lstat(m.Target)
	if errors.Is(err, fs.ErrNotExist) {
		return inspection{State: stateMissing}
	}
	if err != nil {
		return inspection{State: stateConflict, Reason: err.Error(), Locked: true}
	}
	if info.Mode()&fs.ModeSymlink != 0 {
		return inspection{State: stateConflict, Locked: true,
			Reason: "is a symlink; replace it with a regular file or add the block to its destination"}
	}
	if !info.Mode().IsRegular() {
		return inspection{State: stateConflict, Locked: true, Reason: "existing " + kindOf(info)}
	}
	data, err := os.ReadFile(m.Target)
	if err != nil {
		return inspection{State: stateConflict, Reason: err.Error(), Locked: true}
	}
	_, _, body, found, ok := findBlock(string(data))
	switch {
	case !ok:
		return inspection{State: stateConflict, Reason: "unbalanced or repeated ds markers"}
	case !found:
		return inspection{State: stateMissing}
	case body == strings.TrimRight(m.Body, "\n"):
		return inspection{State: statePresent}
	}
	return inspection{State: stateStale}
}

// write appends or replaces the block. With replace on a malformed file it
// strips every marker line and appends a fresh block; the caller backs up
// the original first.
func (m managedBlock) write(replace bool) (Ownership, error) {
	info, err := os.Lstat(m.Target)
	mode := fs.FileMode(0o644)
	var content string
	switch {
	case errors.Is(err, fs.ErrNotExist):
	case err != nil:
		return Ownership{}, err
	case !info.Mode().IsRegular():
		return Ownership{}, fmt.Errorf("%s is not a regular file", m.Target)
	default:
		mode = info.Mode().Perm()
		data, err := os.ReadFile(m.Target)
		if err != nil {
			return Ownership{}, err
		}
		content = string(data)
	}
	block := renderBlock(m.Body)
	start, end, _, found, ok := findBlock(content)
	switch {
	case found:
		content = content[:start] + block + content[end:]
	case !ok:
		content = stripMarkers(content)
		fallthrough
	default:
		if content != "" && !strings.HasSuffix(content, "\n") {
			content += "\n"
		}
		content += block
	}
	if err := writeAtomic(m.Target, []byte(content), mode); err != nil {
		return Ownership{}, err
	}
	return Ownership{Kind: ownBlock}, nil
}

// stripMarkers drops closed blocks and orphan marker lines. Lines after an
// unterminated start marker are user content and stay.
func stripMarkers(content string) string {
	lines := strings.SplitAfter(content, "\n")
	marker := func(i int) string { return strings.TrimRight(lines[i], "\n") }
	var out strings.Builder
	for i := 0; i < len(lines); i++ {
		switch marker(i) {
		case blockEnd:
			continue
		case blockStart:
			j := i + 1
			for j < len(lines) && marker(j) != blockStart && marker(j) != blockEnd {
				j++
			}
			if j < len(lines) && marker(j) == blockEnd {
				i = j
			}
			continue
		}
		out.WriteString(lines[i])
	}
	return out.String()
}

func (m managedFile) inspect(own map[string]Ownership, _ []string) inspection {
	info, err := os.Lstat(m.Target)
	if errors.Is(err, fs.ErrNotExist) {
		return inspection{State: stateMissing}
	}
	if err != nil {
		return inspection{State: stateConflict, Reason: err.Error()}
	}
	if !info.Mode().IsRegular() {
		return inspection{State: stateConflict, Reason: "existing " + kindOf(info)}
	}
	data, err := os.ReadFile(m.Target)
	if err != nil {
		return inspection{State: stateConflict, Reason: err.Error()}
	}
	if bytes.Equal(data, m.Content) && info.Mode().Perm() == m.Mode {
		return inspection{State: statePresent}
	}
	if rec, ok := own[m.Target]; ok && rec.Kind == ownFile && rec.SHA256 == digest(data) {
		return inspection{State: stateStale}
	}
	if bytes.Equal(data, m.Content) {
		return inspection{State: stateStale}
	}
	return inspection{State: stateConflict, Reason: "content differs from what ds wrote"}
}

func (m managedFile) write(bool) (Ownership, error) {
	if err := writeAtomic(m.Target, m.Content, m.Mode); err != nil {
		return Ownership{}, err
	}
	return Ownership{Kind: ownFile, SHA256: digest(m.Content)}, nil
}

func digest(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func kindOf(info fs.FileInfo) string {
	switch {
	case info.IsDir():
		return "directory"
	case info.Mode()&fs.ModeSymlink != 0:
		return "symlink"
	}
	return "file"
}

func within(p, root string) bool {
	root = filepath.Clean(root)
	return p == root || strings.HasPrefix(p, root+string(filepath.Separator))
}

func exists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// backupPath maps a target into an operation's backup directory.
func backupPath(dir, home, target string) string {
	rel, err := filepath.Rel(home, target)
	if err != nil || strings.HasPrefix(rel, "..") {
		rel = filepath.Join("_root", target)
	}
	return filepath.Join(dir, rel)
}

// moveToBackup preserves a conflicting path without overwriting backups.
func moveToBackup(target, backup string) error {
	if _, err := os.Lstat(backup); err == nil {
		return fmt.Errorf("backup already exists: %s", backup)
	}
	if err := os.MkdirAll(filepath.Dir(backup), 0o755); err != nil {
		return err
	}
	return os.Rename(target, backup)
}

// copyToBackup preserves a file that ds edits in place.
func copyToBackup(target, backup string) error {
	if _, err := os.Lstat(backup); err == nil {
		return fmt.Errorf("backup already exists: %s", backup)
	}
	if err := os.MkdirAll(filepath.Dir(backup), 0o755); err != nil {
		return err
	}
	src, err := os.Open(target)
	if err != nil {
		return err
	}
	defer src.Close()
	info, err := src.Stat()
	if err != nil {
		return err
	}
	dst, err := os.OpenFile(backup, os.O_WRONLY|os.O_CREATE|os.O_EXCL, info.Mode().Perm())
	if err != nil {
		return err
	}
	_, err = io.Copy(dst, src)
	return errors.Join(err, dst.Close())
}

// managedJSON sets top-level keys of a user JSON file and leaves the rest.
type managedJSON struct {
	Target string
	Set    map[string]any
}

func (m managedJSON) path() string { return m.Target }

func (m managedJSON) describe() string {
	return "json keys " + strings.Join(slices.Sorted(maps.Keys(m.Set)), ", ") + " in " + m.Target
}

// editsInPlace reports entries that change part of a user file.
func editsInPlace(m managed) bool {
	switch m.(type) {
	case managedBlock, managedJSON:
		return true
	}
	return false
}

// jsonMember is one top-level key with its raw value.
type jsonMember struct {
	Key string
	Raw json.RawMessage
}

// parseJSONObject reads a top-level object, keeping key order. Empty input
// is an empty object.
func parseJSONObject(data []byte) ([]jsonMember, error) {
	if len(bytes.TrimSpace(data)) == 0 {
		return nil, nil
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	if tok, err := dec.Token(); err != nil || tok != json.Delim('{') {
		return nil, errors.New("not a JSON object")
	}
	var members []jsonMember
	for dec.More() {
		tok, err := dec.Token()
		if err != nil {
			return nil, err
		}
		key, _ := tok.(string)
		var raw json.RawMessage
		if err := dec.Decode(&raw); err != nil {
			return nil, err
		}
		members = append(members, jsonMember{Key: key, Raw: raw})
	}
	if _, err := dec.Token(); err != nil {
		return nil, err
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return nil, errors.New("trailing data after JSON object")
	}
	return members, nil
}

// renderJSONObject writes members with two-space indentation.
func renderJSONObject(members []jsonMember) ([]byte, error) {
	if len(members) == 0 {
		return []byte("{}\n"), nil
	}
	var buf bytes.Buffer
	buf.WriteString("{\n")
	for i, member := range members {
		key, err := json.Marshal(member.Key)
		if err != nil {
			return nil, err
		}
		buf.WriteString("  ")
		buf.Write(key)
		buf.WriteString(": ")
		if err := json.Indent(&buf, member.Raw, "  ", "  "); err != nil {
			return nil, err
		}
		if i < len(members)-1 {
			buf.WriteByte(',')
		}
		buf.WriteByte('\n')
	}
	buf.WriteString("}\n")
	return buf.Bytes(), nil
}

// canonicalJSON is a key-sorted encoding that ignores formatting.
func canonicalJSON(v map[string]any) []byte {
	data, _ := json.Marshal(v)
	return data
}

func (m managedJSON) read() (members []jsonMember, mode fs.FileMode, exists bool, err error) {
	info, err := os.Lstat(m.Target)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, 0o644, false, nil
	}
	if err != nil {
		return nil, 0, false, err
	}
	if info.Mode()&fs.ModeSymlink != 0 {
		return nil, 0, false, errors.New("is a symlink; replace it with a regular file or edit its destination")
	}
	if !info.Mode().IsRegular() {
		return nil, 0, false, errors.New("existing " + kindOf(info))
	}
	data, err := os.ReadFile(m.Target)
	if err != nil {
		return nil, 0, false, err
	}
	members, err = parseJSONObject(data)
	if err != nil {
		return nil, 0, false, fmt.Errorf("invalid JSON: %w", err)
	}
	return members, info.Mode().Perm(), true, nil
}

func (m managedJSON) inspect(own map[string]Ownership, _ []string) inspection {
	members, _, exists, err := m.read()
	if err != nil {
		return inspection{State: stateConflict, Reason: err.Error(), Locked: true}
	}
	if !exists {
		return inspection{State: stateMissing}
	}
	current := map[string]any{}
	differs := false
	for key, want := range m.Set {
		i := slices.IndexFunc(members, func(mem jsonMember) bool { return mem.Key == key })
		if i < 0 {
			continue
		}
		var got any
		if err := json.Unmarshal(members[i].Raw, &got); err != nil {
			return inspection{State: stateConflict, Reason: "invalid JSON: " + err.Error(), Locked: true}
		}
		current[key] = got
		if !bytes.Equal(canonicalJSON(map[string]any{key: got}), canonicalJSON(map[string]any{key: want})) {
			differs = true
		}
	}
	switch {
	case differs:
		if rec, ok := own[m.Target]; ok && rec.Kind == ownJSON && rec.SHA256 == digest(canonicalJSON(current)) {
			return inspection{State: stateStale}
		}
		return inspection{State: stateConflict, Reason: "existing values differ for " + m.describe()}
	case len(current) == len(m.Set):
		return inspection{State: statePresent}
	case len(current) == 0:
		return inspection{State: stateMissing}
	}
	return inspection{State: stateStale}
}

func (m managedJSON) write(bool) (Ownership, error) {
	members, mode, _, err := m.read()
	if err != nil {
		return Ownership{}, err
	}
	for _, key := range slices.Sorted(maps.Keys(m.Set)) {
		raw, err := json.Marshal(m.Set[key])
		if err != nil {
			return Ownership{}, err
		}
		if i := slices.IndexFunc(members, func(mem jsonMember) bool { return mem.Key == key }); i >= 0 {
			members[i].Raw = raw
			continue
		}
		members = append(members, jsonMember{Key: key, Raw: raw})
	}
	data, err := renderJSONObject(members)
	if err != nil {
		return Ownership{}, err
	}
	if err := writeAtomic(m.Target, data, mode); err != nil {
		return Ownership{}, err
	}
	return Ownership{Kind: ownJSON, SHA256: digest(canonicalJSON(m.Set))}, nil
}
