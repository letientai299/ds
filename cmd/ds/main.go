// Command ds configures a development environment.
package main

import (
	"context"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	// Minimal hosts may lack a CA bundle; these roots apply only then.
	_ "golang.org/x/crypto/x509roots/fallback"

	"github.com/letientai299/ds/internal/cli"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	exe, err := os.Executable()
	if err == nil {
		exe, _ = filepath.EvalSymlinks(exe)
	}
	code := cli.Run(ctx, os.Args[1:], cli.IO{
		Stdin:       os.Stdin,
		Stdout:      os.Stdout,
		Stderr:      os.Stderr,
		Environ:     os.Environ(),
		Interactive: isTerminal(os.Stdin),
		Executable:  exe,
		UID:         os.Getuid(),
		Exec:        syscall.Exec,
	})
	stop()
	os.Exit(code)
}

func isTerminal(f *os.File) bool {
	info, err := f.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}
