package main

import "testing"

func TestMoveVerticalUsesHorizontalMovementForSingleRow(t *testing.T) {
	if got := moveVertical(2, 5, 5, 1, 1); got != 3 {
		t.Fatalf("down/j on one row = %d, want 3", got)
	}
	if got := moveVertical(2, 5, 5, 1, -1); got != 1 {
		t.Fatalf("up/k on one row = %d, want 1", got)
	}
}

func TestMoveVerticalBetweenRows(t *testing.T) {
	if got := moveVertical(1, 8, 4, 2, 1); got != 5 {
		t.Fatalf("down/j from top row = %d, want 5", got)
	}
	if got := moveVertical(5, 8, 4, 2, -1); got != 1 {
		t.Fatalf("up/k from bottom row = %d, want 1", got)
	}
}

func TestMoveVerticalFallsBackToHorizontalWhenNoVerticalTarget(t *testing.T) {
	if got := moveVertical(3, 7, 4, 2, 1); got != 4 {
		t.Fatalf("down/j from top cell without lower neighbor = %d, want 4", got)
	}
	if got := moveVertical(5, 7, 4, 2, 1); got != 6 {
		t.Fatalf("down/j from bottom row = %d, want 6", got)
	}
	if got := moveVertical(2, 7, 4, 2, -1); got != 1 {
		t.Fatalf("up/k from top row = %d, want 1", got)
	}
}
