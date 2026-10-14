package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func fakeTmux(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "commands")
	bin := filepath.Join(dir, "tmux")
	if err := os.WriteFile(bin, []byte("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$TMUX_TEST_LOG\"\nif [ \"$1\" = list-clients ]; then printf '%s\\n' \"$TMUX_TEST_CLIENTS\"; fi\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("TMUX_BIN", bin)
	t.Setenv("TMUX_TEST_LOG", log)
	return log
}

func TestHighlightedSessionPreviewsOnOpenAndNavigation(t *testing.T) {
	log := fakeTmux(t)
	m := initialModel([]string{"original", "second", "third"})
	m.client = "/dev/ttys123"
	m.Init()
	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyTab})
	m = updated.(model)
	updated, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'h'}})
	m = updated.(model)
	m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'x'}})
	data, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	want := ""
	for _, session := range []string{"second", "third", "second"} {
		want += "switch-client -E -c /dev/ttys123 -t =" + session + " ; run-shell true\n"
	}
	if string(data) != want {
		t.Fatalf("commands = %q, want %q", data, want)
	}
}

func TestConfirmAndCancel(t *testing.T) {
	for _, key := range []tea.KeyMsg{
		{Type: tea.KeyEnter}, {Type: tea.KeyEsc}, {Type: tea.KeyCtrlC},
		{Type: tea.KeyRunes, Runes: []rune{'q'}},
	} {
		t.Run(key.String(), func(t *testing.T) {
			m := initialModel([]string{"original", "second"})
			updated, cmd := m.Update(key)
			final := updated.(model)
			if final.confirmed != (key.Type == tea.KeyEnter) {
				t.Fatalf("confirmed = %v for %s", final.confirmed, key.String())
			}
			if cmd == nil {
				t.Fatal("expected quit command")
			}
			if _, ok := cmd().(tea.QuitMsg); !ok {
				t.Fatal("expected quit message")
			}
		})
	}
}

func TestSwitchClientUsesExplicitClientAndSessionID(t *testing.T) {
	log := fakeTmux(t)
	if err := tmuxSwitchClient("/dev/ttys123", "$42"); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "-c /dev/ttys123 -t $42") {
		t.Fatalf("unexpected command: %s", data)
	}
}

func TestClientSessionTargetsOriginatingClient(t *testing.T) {
	fakeTmux(t)
	t.Setenv("TMUX_TEST_CLIENTS", "/dev/ttys111\t$1\toriginal\n/dev/ttys222\t$2\tother")
	id, name, err := tmuxClientSession("/dev/ttys111")
	if err != nil || id != "$1" || name != "original" {
		t.Fatalf("client session = %q, %q, %v", id, name, err)
	}
	if _, _, err := tmuxClientSession("/dev/missing"); err == nil {
		t.Fatal("missing client should return an error")
	}
}

func TestPreviewMarkerOwnershipAndStaleRecovery(t *testing.T) {
	path := filepath.Join(t.TempDir(), "preview")
	if err := startPreviewMarker(path); err != nil {
		t.Fatal(err)
	}
	if err := startPreviewMarker(path); err == nil {
		t.Fatal("must not replace a live process's marker")
	}
	if err := os.WriteFile(path, []byte("999999999\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := startPreviewMarker(path); err != nil {
		t.Fatalf("reclaim stale marker: %v", err)
	}
}

func TestLivePreviewEnabled(t *testing.T) {
	for _, value := range []string{"", "on", "off", " off "} {
		t.Run(value, func(t *testing.T) {
			t.Setenv("TMUX_TAB_LIVE_PREVIEW", value)
			want := strings.TrimSpace(value) != "off"
			if got := livePreviewEnabled(); got != want {
				t.Fatalf("livePreviewEnabled() = %v, want %v", got, want)
			}
		})
	}
}

func TestDisabledLivePreviewDoesNotSwitchOnOpenOrNavigation(t *testing.T) {
	log := fakeTmux(t)
	t.Setenv("TMUX_TAB_LIVE_PREVIEW", "off")
	m := initialModel([]string{"original", "second", "third"})
	m.client = "/dev/ttys123"
	m.Init()
	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyTab})
	m = updated.(model)
	if m.selected != 2 {
		t.Fatalf("selected = %d, want 2", m.selected)
	}
	if _, err := os.Stat(log); !os.IsNotExist(err) {
		t.Fatalf("disabled preview should not run tmux, stat error: %v", err)
	}
	updated, _ = m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if !updated.(model).confirmed {
		t.Fatal("Enter should still confirm with live preview disabled")
	}
}
