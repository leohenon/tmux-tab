package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

const defaultMaxSessions = 7
const minMaxSessions = 5
const absoluteMaxSessions = 12
const previewRefreshInterval = 500 * time.Millisecond
const preferredCardOuterWidth = 46
const preferredPreviewHeight = 12
const minCardOuterWidth = 12
const maxCardOuterWidth = 46
const minPreviewHeight = 3
const previewAspectDivisor = 3

func tmuxBin() string {
	if bin := os.Getenv("TMUX_BIN"); bin != "" {
		return bin
	}
	return "tmux"
}

func livePreviewEnabled() bool {
	return strings.TrimSpace(os.Getenv("TMUX_TAB_LIVE_PREVIEW")) != "off"
}

func highlightColor() string {
	if color := strings.TrimSpace(os.Getenv("TMUX_TAB_COLOR")); color != "" {
		return color
	}
	return "62"
}

func highlightTextColor() string {
	if color := strings.TrimSpace(os.Getenv("TMUX_TAB_TEXT_COLOR")); color != "" {
		return color
	}
	return "15"
}

const (
	previewAnchorLeft   = "bottom-left"
	previewAnchorRight  = "bottom-right"
	previewAnchorCursor = "cursor"
)

func previewAnchor() string {
	switch strings.TrimSpace(os.Getenv("TMUX_TAB_PREVIEW_ANCHOR")) {
	case previewAnchorRight:
		return previewAnchorRight
	case previewAnchorCursor:
		return previewAnchorCursor
	default:
		return previewAnchorLeft
	}
}

func maxVisibleSessions() int {
	value := strings.TrimSpace(os.Getenv("TMUX_TAB_MAX_TABS"))
	if value == "" {
		return defaultMaxSessions
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return defaultMaxSessions
	}
	if parsed < minMaxSessions {
		return minMaxSessions
	}
	if parsed > absoluteMaxSessions {
		return absoluteMaxSessions
	}
	return parsed
}

func tmuxCmd(args ...string) (string, error) {
	cmd := exec.Command(tmuxBin(), args...)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimRight(string(out), "\n"), nil
}

func tmuxServerPID() string {
	pid, _ := tmuxCmd("display-message", "-p", "#{pid}")
	return pid
}

func tmuxListSessions() []string {
	out, err := tmuxCmd("list-sessions", "-F", "#{session_name}")
	if err != nil {
		return nil
	}
	var sessions []string
	for _, s := range strings.Split(out, "\n") {
		s = strings.TrimSpace(s)
		if s != "" {
			sessions = append(sessions, s)
		}
	}
	return sessions
}

func tmuxClientSession(client string) (id, name string, err error) {
	out, err := tmuxCmd("list-clients", "-F", "#{client_name}\t#{session_id}\t#{session_name}")
	if err != nil {
		return "", "", err
	}
	for _, line := range strings.Split(out, "\n") {
		fields := strings.SplitN(line, "\t", 3)
		if len(fields) == 3 && fields[0] == client {
			return fields[1], fields[2], nil
		}
	}
	return "", "", fmt.Errorf("tmux client %q is not attached", client)
}

func tmuxSwitchClient(client, session string) error {
	// The trailing command waits for session-change hooks before cleanup.
	_, err := tmuxCmd("switch-client", "-E", "-c", client, "-t", session,
		";", "run-shell", "true")
	return err
}

func blankPreviewLine(line string) bool {
	stripped := strings.TrimSpace(ansi.Strip(line))
	return stripped == "" || stripped == "~"
}

const tabWidth = 8

func expandTabs(line string) string {
	if !strings.ContainsRune(line, '\t') {
		return line
	}
	var b strings.Builder
	col := 0
	for i := 0; i < len(line); {
		if line[i] == '\t' {
			spaces := tabWidth - (col % tabWidth)
			for s := 0; s < spaces; s++ {
				b.WriteByte(' ')
			}
			col += spaces
			i++
			continue
		}
		if line[i] == '\x1b' {
			j := i + 1
			for j < len(line) && !isANSITerminator(line[j]) {
				j++
			}
			if j < len(line) {
				j++
			}
			b.WriteString(line[i:j])
			i = j
			continue
		}
		_, size := utf8.DecodeRuneInString(line[i:])
		b.WriteString(line[i : i+size])
		col++
		i += size
	}
	return b.String()
}

func isANSITerminator(c byte) bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

type paneCapture struct {
	lines       []string
	cursorX     int
	cursorY     int
	cursorValid bool
}

func parseCursorLine(line string) (int, int, bool) {
	fields := strings.Fields(line)
	if len(fields) != 2 {
		return 0, 0, false
	}
	x, errX := strconv.Atoi(fields[0])
	y, errY := strconv.Atoi(fields[1])
	if errX != nil || errY != nil {
		return 0, 0, false
	}
	return x, y, true
}

func tmuxCapturePane(session string, wantCursor bool) paneCapture {
	var out string
	var err error
	if wantCursor {
		out, err = tmuxCmd("capture-pane", "-e", "-t", session+":", "-p",
			";", "display-message", "-p", "-t", session+":", "#{cursor_x} #{cursor_y}")
	} else {
		out, err = tmuxCmd("capture-pane", "-e", "-t", session+":", "-p")
	}
	if err != nil {
		return paneCapture{}
	}
	allLines := strings.Split(out, "\n")
	var cursorX, cursorY int
	var cursorValid bool
	if wantCursor && len(allLines) > 0 {
		cursorX, cursorY, cursorValid = parseCursorLine(allLines[len(allLines)-1])
		allLines = allLines[:len(allLines)-1]
	}
	for i, line := range allLines {
		allLines[i] = expandTabs(line)
	}
	for len(allLines) > 0 && blankPreviewLine(allLines[len(allLines)-1]) {
		allLines = allLines[:len(allLines)-1]
	}
	start := 0
	for start < len(allLines) && blankPreviewLine(allLines[start]) {
		start++
	}
	return paneCapture{
		lines:       allLines[start:],
		cursorX:     cursorX,
		cursorY:     cursorY - start,
		cursorValid: cursorValid,
	}
}

func truncate(s string, max int) string {
	runes := []rune(s)
	if len(runes) > max {
		return string(runes[:max-1]) + "…"
	}
	return s
}

func windowLine(line string, width int, anchor string, cap paneCapture, isCursorRow bool) string {
	if width <= 0 {
		return ""
	}
	lineW := ansi.StringWidth(line)
	if lineW <= width {
		return line
	}

	var out string
	switch anchor {
	case previewAnchorRight:
		out = "…" + ansi.TruncateLeft(line, lineW-width+1, "")
	case previewAnchorCursor:
		if cap.cursorValid && isCursorRow {
			left := cap.cursorX - width/2
			if left > lineW-width {
				left = lineW - width
			}
			if left < 0 {
				left = 0
			}
			seg := ansi.Cut(line, left, left+width)
			if left > 0 {
				seg = "…" + ansi.Cut(seg, 1, width)
			}
			if left+width < lineW {
				seg = ansi.Cut(seg, 0, width-1) + "…"
			}
			out = seg
		} else {
			out = ansi.Truncate(line, width, "…")
		}
	default:
		out = ansi.Truncate(line, width, "…")
	}

	if ansi.StringWidth(out) > width {
		out = ansi.Truncate(out, width, "")
	}
	return out
}

func mruFilePath() string {
	pid := tmuxServerPID()
	return filepath.Join("/tmp", "tmux-tab-mru-v2-"+pid)
}

func readMRU() []string {
	liveSessions := tmuxListSessions()
	if len(liveSessions) == 0 {
		return nil
	}

	liveSet := make(map[string]bool)
	for _, s := range liveSessions {
		liveSet[s] = true
	}

	var mruList []string
	seen := make(map[string]bool)
	var currentSession string
	if client := os.Getenv("TMUX_TAB_CLIENT"); client != "" {
		_, currentSession, _ = tmuxClientSession(client)
	} else {
		currentSession, _ = tmuxCmd("display-message", "-p", "#{session_name}")
	}
	if currentSession != "" && liveSet[currentSession] {
		mruList = append(mruList, currentSession)
		seen[currentSession] = true
	}

	file, err := os.Open(mruFilePath())
	if err == nil {
		defer file.Close()
		scanner := bufio.NewScanner(file)
		for scanner.Scan() {
			name := strings.TrimSpace(scanner.Text())
			if name != "" && liveSet[name] && !seen[name] {
				mruList = append(mruList, name)
				seen[name] = true
			}
		}
	}

	return mruList
}

type previewsLoadedMsg struct {
	previews map[string]paneCapture
}

type previewTickMsg time.Time

func captureAllPreviews(sessions []string) tea.Cmd {
	return func() tea.Msg {
		previews := make(map[string]paneCapture)
		wantCursor := previewAnchor() == previewAnchorCursor
		var mu sync.Mutex
		var wg sync.WaitGroup

		for _, s := range sessions {
			wg.Add(1)
			go func(name string) {
				defer wg.Done()
				cap := tmuxCapturePane(name, wantCursor)
				mu.Lock()
				previews[name] = cap
				mu.Unlock()
			}(s)
		}

		wg.Wait()
		return previewsLoadedMsg{previews: previews}
	}
}

func previewTick() tea.Cmd {
	return tea.Tick(previewRefreshInterval, func(t time.Time) tea.Msg {
		return previewTickMsg(t)
	})
}

type model struct {
	livePreview bool
	client      string
	confirmed   bool
	sessions    []string
	selected    int
	width       int
	height      int
	previews    map[string]paneCapture
}

type layout struct {
	cols          int
	rows          int
	cardOuterW    int
	cardInnerW    int
	previewH      int
	horizontalGap int
	verticalGap   int
}

func ceilDiv(a, b int) int {
	if b <= 0 {
		return 0
	}
	return (a + b - 1) / b
}

func computeLayout(width, height, count int) layout {
	rows := 1
	if count > 5 {
		rows = 2
	}
	cols := ceilDiv(count, rows)
	hGap := 1
	vGap := 1

	cardOuterW := preferredCardOuterWidth
	if neededWidth := cols*cardOuterW + (cols-1)*hGap; neededWidth > width {
		cardOuterW = max(minCardOuterWidth, min(maxCardOuterWidth, (width-(cols-1)*hGap)/cols))
	}
	cardInnerW := max(4, cardOuterW-2)

	maxPreviewByHeight := ((height - (rows-1)*vGap) / rows) - 3
	previewTarget := preferredPreviewHeight
	if cardOuterW != preferredCardOuterWidth {
		previewTarget = max(minPreviewHeight, cardInnerW/previewAspectDivisor)
	}
	previewH := min(previewTarget, maxPreviewByHeight)
	if previewH < 1 {
		previewH = 1
	}

	return layout{
		cols:          cols,
		rows:          rows,
		cardOuterW:    cardOuterW,
		cardInnerW:    cardInnerW,
		previewH:      previewH,
		horizontalGap: hGap,
		verticalGap:   vGap,
	}
}

func initialModel(sessions []string) model {
	maxSessions := maxVisibleSessions()
	if len(sessions) > maxSessions {
		sessions = sessions[:maxSessions]
	}

	selected := 1
	if selected >= len(sessions) {
		selected = 0
	}

	return model{
		livePreview: livePreviewEnabled(),
		sessions:    sessions,
		selected:    selected,
		previews:    nil,
	}
}

func (m model) previewSelection() {
	if m.livePreview && m.client != "" && len(m.sessions) > 0 {
		_ = tmuxSwitchClient(m.client, "="+m.sessions[m.selected])
	}
}

func (m model) Init() tea.Cmd {
	m.previewSelection()
	return tea.Batch(
		captureAllPreviews(m.sessions),
		previewTick(),
	)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case previewsLoadedMsg:
		m.previews = msg.previews
		return m, nil

	case previewTickMsg:
		return m, tea.Batch(
			captureAllPreviews(m.sessions),
			previewTick(),
		)

	case tea.KeyMsg:
		previous := m.selected
		switch msg.String() {
		case "tab", "right", "l", "down", "j":
			m.selected = (m.selected + 1) % len(m.sessions)
		case "shift+tab", "left", "h", "up", "k":
			m.selected = (m.selected - 1 + len(m.sessions)) % len(m.sessions)
		case "enter":
			m.confirmed = true
			return m, tea.Quit
		case "esc", "q", "ctrl+c":
			return m, tea.Quit
		}
		if m.selected != previous {
			m.previewSelection()
		}
	}

	return m, nil
}

func (m model) View() string {
	if len(m.sessions) == 0 || m.width == 0 || m.height == 0 {
		return ""
	}

	w := m.width
	h := m.height
	n := len(m.sessions)
	l := computeLayout(w, h, n)
	highlight := highlightColor()
	textColor := highlightTextColor()
	anchor := previewAnchor()

	nameSelectedStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color(textColor)).
		Background(lipgloss.Color(highlight)).
		Width(l.cardOuterW).
		Align(lipgloss.Center)
	nameNormalStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("250")).
		Width(l.cardOuterW).
		Align(lipgloss.Center)
	contentW := max(4, l.cardInnerW-2)
	boxMaxH := l.previewH + 2
	previewSelectedStyle := lipgloss.NewStyle().
		Width(l.cardInnerW).
		Height(l.previewH).
		MaxHeight(boxMaxH).
		Padding(0, 1).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color(highlight))
	previewNormalStyle := lipgloss.NewStyle().
		Width(l.cardInnerW).
		Height(l.previewH).
		MaxHeight(boxMaxH).
		Padding(0, 1).
		Foreground(lipgloss.Color("244")).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("238"))
	placeholderStyle := lipgloss.NewStyle().
		Width(contentW).
		Height(l.previewH).
		Align(lipgloss.Center, lipgloss.Center).
		Foreground(lipgloss.Color("240")).
		Italic(true)

	var cards []string
	for i, s := range m.sessions {
		label := truncate(s, l.cardOuterW-2)
		selected := i == m.selected

		var previewLines []string
		if m.previews != nil {
			if cap, ok := m.previews[s]; ok {
				lines := cap.lines
				trimmed := 0
				if len(lines) > l.previewH {
					trimmed = len(lines) - l.previewH
					lines = lines[trimmed:]
				}
				cursorRow := cap.cursorY - trimmed
				for row, line := range lines {
					windowed := windowLine(line, contentW, anchor, cap, cursorRow == row)
					if selected {
						previewLines = append(previewLines, windowed)
					} else {
						previewLines = append(previewLines, ansi.Strip(windowed))
					}
				}
			}
		}

		var name, prev string
		if selected {
			name = nameSelectedStyle.Render(label)
		} else {
			name = nameNormalStyle.Render(label)
		}

		if len(previewLines) == 0 {
			body := placeholderStyle.Render("— no output —")
			if selected {
				prev = previewSelectedStyle.Render(body)
			} else {
				prev = previewNormalStyle.Render(body)
			}
		} else {
			preview := strings.Join(previewLines, "\n")
			if selected {
				prev = previewSelectedStyle.Render(preview)
			} else {
				prev = previewNormalStyle.Render(preview)
			}
		}

		card := lipgloss.JoinVertical(lipgloss.Center, name, prev)
		cards = append(cards, card)
	}

	var rows []string
	for start := 0; start < len(cards); start += l.cols {
		end := min(start+l.cols, len(cards))
		rowCards := make([]string, 0, end-start)
		for i, card := range cards[start:end] {
			if i < end-start-1 {
				card = lipgloss.NewStyle().MarginRight(l.horizontalGap).Render(card)
			}
			rowCards = append(rowCards, card)
		}
		row := lipgloss.JoinHorizontal(lipgloss.Top, rowCards...)
		placed := lipgloss.PlaceHorizontal(w, lipgloss.Center, row)
		if end < len(cards) {
			placed = lipgloss.NewStyle().MarginBottom(l.verticalGap).Render(placed)
		}
		rows = append(rows, placed)
	}

	grid := lipgloss.JoinVertical(lipgloss.Top, rows...)
	return lipgloss.Place(w, h, lipgloss.Center, lipgloss.Center, grid)
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func startPreviewMarker(path string) error {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if os.IsExist(err) {
		data, readErr := os.ReadFile(path)
		pid, parseErr := strconv.Atoi(strings.TrimSpace(string(data)))
		if readErr == nil && parseErr == nil && pid > 0 && syscall.Kill(pid, 0) == syscall.ESRCH {
			if err = os.Remove(path); err == nil {
				file, err = os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
			}
		}
	}
	if err != nil {
		return err
	}
	_, err = fmt.Fprintln(file, os.Getpid())
	closeErr := file.Close()
	if err != nil {
		os.Remove(path)
		return err
	}
	return closeErr
}

func run() error {
	sessions := readMRU()
	if len(sessions) <= 1 {
		return nil
	}

	client := os.Getenv("TMUX_TAB_CLIENT")
	if client == "" {
		client, _ = tmuxCmd("display-message", "-p", "#{client_name}")
	}
	if client == "" {
		return fmt.Errorf("cannot identify tmux client")
	}
	original, _, err := tmuxClientSession(client)
	if err != nil || original == "" {
		return fmt.Errorf("cannot identify original session for %q", client)
	}
	m := initialModel(sessions)
	var marker string
	if m.livePreview {
		marker = filepath.Join("/tmp", "tmux-tab-preview-"+tmuxServerPID()+"-"+filepath.Base(client))
		if err := startPreviewMarker(marker); err != nil {
			return fmt.Errorf("start session preview: %w", err)
		}
		defer os.Remove(marker)
	}
	m.client = client
	p := tea.NewProgram(m, tea.WithAltScreen())
	// Closing a popup's PTY sends SIGHUP; treat it like cancel as well.
	hangup := make(chan os.Signal, 1)
	done := make(chan struct{})
	signal.Notify(hangup, syscall.SIGHUP)
	defer signal.Stop(hangup)
	defer close(done)
	go func() {
		select {
		case <-hangup:
			p.Quit()
		case <-done:
		}
	}()
	result, runErr := p.Run()
	final, ok := result.(model)
	if runErr != nil || !ok || !final.confirmed {
		// Restore while the marker still suppresses MRU updates.
		if m.livePreview {
			err = tmuxSwitchClient(client, original)
		}
	} else {
		// The final switch is a real visit, including if already previewed.
		if marker != "" {
			err = os.Remove(marker)
		}
		if err == nil {
			err = tmuxSwitchClient(client, "="+final.sessions[final.selected])
		}
	}
	if runErr != nil {
		return runErr
	}
	return err
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
