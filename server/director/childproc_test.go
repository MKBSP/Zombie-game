package director

import (
	"os/exec"
	"testing"
	"time"
)

func TestExecChild_DoneClosesWhenProcessExits(t *testing.T) {
	ch, err := startProcess(exec.Command("sleep", "0.2"), 8911, "AB3K")
	if err != nil {
		t.Fatalf("startProcess: %v", err)
	}
	if ch.Port() != 8911 || ch.Code() != "AB3K" {
		t.Errorf("port/code = %d/%q, want 8911/AB3K", ch.Port(), ch.Code())
	}
	select {
	case <-ch.Done():
		t.Fatal("Done closed before the process exited")
	default:
	}
	select {
	case <-ch.Done():
	case <-time.After(2 * time.Second):
		t.Fatal("Done never closed after the process exited")
	}
}

func TestExecChild_KillTerminates(t *testing.T) {
	ch, err := startProcess(exec.Command("sleep", "10"), 8912, "QF7P")
	if err != nil {
		t.Fatalf("startProcess: %v", err)
	}
	ch.Kill()
	select {
	case <-ch.Done():
	case <-time.After(2 * time.Second):
		t.Fatal("Done never closed after Kill")
	}
}
