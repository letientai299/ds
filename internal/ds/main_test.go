package ds

import (
	"os"
	"testing"
)

func TestMain(m *testing.M) {
	retryDelay = 0
	os.Exit(m.Run())
}
