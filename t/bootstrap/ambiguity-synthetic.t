# ABOUTME: Regression tests for Boolean::add() call counts on synthetic grammars with known ambiguity.
# ABOUTME: Asserts Earley invokes add() exactly for genuine nested-nonterminal ambiguity, no more, no less.
use 5.42.0;
use utf8;
use Test::More;
binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

sub terminal($value) {
    Chalk::Grammar::Symbol->new(type => 'terminal', value => $value);
}
sub reference($value) {
    Chalk::Grammar::Symbol->new(type => 'reference', value => $value);
}

# Monkey-patch Boolean::add to count both-non-zero calls per parse.
# Both-non-zero is the ambiguity-merge case — what we actually want to measure.
our $both_nz = 0;
my $orig_add = \&Chalk::Bootstrap::Semiring::Boolean::add;
no warnings 'redefine';
*Chalk::Bootstrap::Semiring::Boolean::add = sub {
    my ($self, $left, $right) = @_;
    $both_nz++ if !$self->is_zero($left) && !$self->is_zero($right);
    return $orig_add->($self, $left, $right);
};

sub count_merges($grammar, $input) {
    local $both_nz = 0;
    my $sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $p  = Chalk::Bootstrap::Earley->new(grammar => $grammar, semiring => $sr);
    my $ok = $p->parse($input);
    return ($ok, $both_nz);
}

# -----------------------------------------------------------------------------
# Grammar 1: E ::= E '+' E | /\d+/    (both-recursive, ambiguous)
#
# Parses of `1+2+...+n` correspond to binary trees with n leaves. The count
# is the Catalan number C(n-1): 1, 1, 2, 5, 14, ... merges needed to
# reduce k parses down to 1 = k-1.
# -----------------------------------------------------------------------------
{
    my $g = [
        Chalk::Grammar::Rule->new(
            name => 'E',
            expressions => [
                [reference('E'), terminal('\+'), reference('E')],
                [terminal('\d+')],
            ],
        ),
    ];

    my ($ok, $n);

    ($ok, $n) = count_merges($g, '1');
    ok($ok, 'G1: parses "1"');
    is($n, 0, 'G1: "1" is unambiguous — 0 merges');

    ($ok, $n) = count_merges($g, '1+2');
    ok($ok, 'G1: parses "1+2"');
    is($n, 0, 'G1: "1+2" is unambiguous — 0 merges');

    ($ok, $n) = count_merges($g, '1+2+3');
    ok($ok, 'G1: parses "1+2+3"');
    is($n, 1, 'G1: "1+2+3" has 2 derivations — 1 merge');

    ($ok, $n) = count_merges($g, '1+2+3+4');
    ok($ok, 'G1: parses "1+2+3+4"');
    is($n, 4, 'G1: "1+2+3+4" has 5 derivations (Catalan C(3)) — 4 merges');
}

# -----------------------------------------------------------------------------
# Grammar 2: E ::= N '+' E | N    (right-recursive, unambiguous)
# Every input has exactly 1 derivation — zero merges.
# -----------------------------------------------------------------------------
{
    my $g = [
        Chalk::Grammar::Rule->new(
            name => 'E',
            expressions => [
                [reference('N'), terminal('\+'), reference('E')],
                [reference('N')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name => 'N',
            expressions => [[terminal('\d+')]],
        ),
    ];

    for my $input ('1', '1+2', '1+2+3', '1+2+3+4') {
        my ($ok, $n) = count_merges($g, $input);
        ok($ok, "G2 (right-rec): parses '$input'");
        is($n, 0, "G2 (right-rec): '$input' — 0 merges (unambiguous)");
    }
}

# -----------------------------------------------------------------------------
# Grammar 3: E ::= E '+' N | N    (left-recursive, unambiguous)
# Every input has exactly 1 derivation — zero merges.
# Different shape from G2 — tests Leo path independently.
# -----------------------------------------------------------------------------
{
    my $g = [
        Chalk::Grammar::Rule->new(
            name => 'E',
            expressions => [
                [reference('E'), terminal('\+'), reference('N')],
                [reference('N')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name => 'N',
            expressions => [[terminal('\d+')]],
        ),
    ];

    for my $input ('1', '1+2', '1+2+3', '1+2+3+4') {
        my ($ok, $n) = count_merges($g, $input);
        ok($ok, "G3 (left-rec): parses '$input'");
        is($n, 0, "G3 (left-rec): '$input' — 0 merges (unambiguous)");
    }
}

# -----------------------------------------------------------------------------
# Grammar 4: S ::= E ';' ; E ::= E '+' E | /\d+/    (wrapped, ambiguous)
# Same ambiguity as G1 wrapped in an extra layer. Counts must not inflate.
# -----------------------------------------------------------------------------
{
    my $g = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [[reference('E'), terminal(';')]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'E',
            expressions => [
                [reference('E'), terminal('\+'), reference('E')],
                [terminal('\d+')],
            ],
        ),
    ];

    my @cases = ( ['1;', 0], ['1+2;', 0], ['1+2+3;', 1], ['1+2+3+4;', 4] );
    for my $case (@cases) {
        my ($input, $expected) = @$case;
        my ($ok, $n) = count_merges($g, $input);
        ok($ok, "G4 (wrapped): parses '$input'");
        is($n, $expected, "G4 (wrapped): '$input' — $expected merges (same as G1 counts)");
    }
}

# -----------------------------------------------------------------------------
# Grammar 5: S ::= E | E    (literal duplicate start-rule alternatives)
#
# This grammar's "ambiguity" is at the top-level alternative-selection
# layer, NOT at nested-nonterminal merge points. Earley seeds chart[0]
# with one item PER start-rule alternative (different core_ids for
# (S, alt 0) vs (S, alt 1)) and the two items never converge on a single
# chart slot. _run_parse's final-slot extraction iterates alternatives
# and returns the first one that completes, so the second is silently
# dropped.
#
# Consequently `add()` is NEVER invoked for this grammar. The test is
# not a bug — it documents a real behavioral distinction between
# top-level rule-alt ambiguity (invisible to add) and nested
# nonterminal ambiguity (visible to add).
#
# This case is kept here to guard against the distinction disappearing
# silently — if a future refactor makes `add` fire here, that means
# top-level alternative merging has been introduced, which would be
# worth noticing and documenting.
# -----------------------------------------------------------------------------
{
    my $g = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [
                [reference('E')],
                [reference('E')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name => 'E',
            expressions => [[terminal('\d+')]],
        ),
    ];

    my ($ok, $n) = count_merges($g, '42');
    ok($ok, 'G5 (dup start-alts): parses "42"');
    is($n, 0,
        'G5 (dup start-alts): "42" — 0 merges (top-level alt-selection is not a nested merge)');
}

done_testing();
