# ABOUTME: Single item in a Chalk::IR::Schedule — a statement or structural marker.
# ABOUTME: kind ∈ qw(stmt block_open block_close else elsif catch); node optional; form for blocks.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::IR::Schedule::Item {
    # 'stmt' | 'block_open' | 'block_close' | 'else' | 'elsif' | 'catch' | 'loop_jump'
    field $kind :param :reader;

    # The IR node this item references. Required for stmt, block_open, loop_jump;
    # optional for block_close / else / elsif / catch.
    field $node :param :reader = undef;

    # For block_open / block_close: 'if' | 'while' | 'for' | 'foreach' | 'try'.
    # For elsif: the new If's surface form (mirrors block_open).
    # Undef for plain statements.
    field $form :param :reader = undef;

    # For loop_jump: the jump keyword ('next' or 'last').
    # The node field carries the If node whose condition is the guard.
    field $jump_keyword :param :reader = undef;
}
