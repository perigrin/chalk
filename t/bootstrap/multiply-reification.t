# ABOUTME: Tests for Earley context annotation helpers _make_scan_context and _make_complete_context.
# ABOUTME: Verifies Context objects produced for scan and complete events carry correct annotations.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Context;

# Build a minimal parser instance to call the helper methods on.
# We use the simplest possible grammar: Start ::= /a/
my $grammar = [
    Chalk::Grammar::Rule->new(
        name        => 'Start',
        expressions => [[
            Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a'),
        ]],
    ),
];
my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
my $parser = Chalk::Bootstrap::Earley->new(
    grammar  => $grammar,
    semiring => $semiring,
);

# -------------------------------------------------------------------------
# _make_scan_context tests
# -------------------------------------------------------------------------

# Test 1: _make_scan_context returns a Context object
{
    my $ctx = $parser->_make_scan_context('hello', 'Identifier', 0, 3);
    isa_ok($ctx, 'Chalk::Bootstrap::Context', '_make_scan_context returns a Context');
}

# Test 2: focus is the matched text
{
    my $ctx = $parser->_make_scan_context('hello', 'Identifier', 0, 3);
    is($ctx->focus(), 'hello', '_make_scan_context: focus is matched_text');
}

# Test 3: annotations contain scan => true
{
    my $ctx = $parser->_make_scan_context('hello', 'Identifier', 0, 3);
    my $ann = $ctx->annotations();
    ok($ann->{scan}, '_make_scan_context: annotations->{scan} is true');
}

# Test 4: annotations contain rule_name
{
    my $ctx = $parser->_make_scan_context('hello', 'Identifier', 0, 3);
    is($ctx->annotations()->{rule_name}, 'Identifier',
        '_make_scan_context: annotations->{rule_name} is correct');
}

# Test 5: annotations contain alt_idx
{
    my $ctx = $parser->_make_scan_context('hello', 'Identifier', 2, 3);
    is($ctx->annotations()->{alt_idx}, 2,
        '_make_scan_context: annotations->{alt_idx} is correct');
}

# Test 6: annotations contain predicted (predicted_at value)
{
    my $ctx = $parser->_make_scan_context('hello', 'Identifier', 0, 7);
    is($ctx->annotations()->{predicted}, 7,
        '_make_scan_context: annotations->{predicted} is correct');
}

# Test 7: position defaults to 0
{
    my $ctx = $parser->_make_scan_context('hi', 'Rule', 1, 5);
    is($ctx->position(), 0, '_make_scan_context: position defaults to 0');
}

# Test 8: children is empty (scan produces a leaf context)
{
    my $ctx = $parser->_make_scan_context('hi', 'Rule', 1, 5);
    is(scalar $ctx->children()->@*, 0,
        '_make_scan_context: children is empty');
}

# -------------------------------------------------------------------------
# _make_complete_context tests
# -------------------------------------------------------------------------

# Test 9: _make_complete_context returns a Context object
{
    my $value = Chalk::Bootstrap::Context->new(focus => 'leaf');
    my $ctx = $parser->_make_complete_context($value, 'Expression', 0, 4, 1);
    isa_ok($ctx, 'Chalk::Bootstrap::Context',
        '_make_complete_context returns a Context');
}

# Test 10: focus is undef (wraps value as child)
{
    my $value = Chalk::Bootstrap::Context->new(focus => 'leaf');
    my $ctx = $parser->_make_complete_context($value, 'Expression', 0, 4, 1);
    is($ctx->focus(), undef, '_make_complete_context: focus is undef');
}

# Test 11: children contains the wrapped value
{
    my $value = Chalk::Bootstrap::Context->new(focus => 'leaf');
    my $ctx = $parser->_make_complete_context($value, 'Expression', 0, 4, 1);
    my @children = $ctx->children()->@*;
    is(scalar @children, 1, '_make_complete_context: has one child');
    is(refaddr($children[0]), refaddr($value),
        '_make_complete_context: child is the wrapped value');
}

# Test 12: annotations contain complete => true
{
    my $value = Chalk::Bootstrap::Context->new(focus => 'leaf');
    my $ctx = $parser->_make_complete_context($value, 'Expression', 0, 4, 1);
    ok($ctx->annotations()->{complete},
        '_make_complete_context: annotations->{complete} is true');
}

# Test 13: annotations contain rule_name
{
    my $value = Chalk::Bootstrap::Context->new(focus => 'leaf');
    my $ctx = $parser->_make_complete_context($value, 'Expression', 0, 4, 1);
    is($ctx->annotations()->{rule_name}, 'Expression',
        '_make_complete_context: annotations->{rule_name} is correct');
}

# Test 14: annotations contain alt_idx
{
    my $value = Chalk::Bootstrap::Context->new(focus => 'leaf');
    my $ctx = $parser->_make_complete_context($value, 'Expression', 2, 4, 1);
    is($ctx->annotations()->{alt_idx}, 2,
        '_make_complete_context: annotations->{alt_idx} is correct');
}

# Test 15: annotations contain pos
{
    my $value = Chalk::Bootstrap::Context->new(focus => 'leaf');
    my $ctx = $parser->_make_complete_context($value, 'Expression', 0, 4, 1);
    is($ctx->annotations()->{pos}, 4,
        '_make_complete_context: annotations->{pos} is correct');
}

# Test 16: annotations contain origin
{
    my $value = Chalk::Bootstrap::Context->new(focus => 'leaf');
    my $ctx = $parser->_make_complete_context($value, 'Expression', 0, 4, 1);
    is($ctx->annotations()->{origin}, 1,
        '_make_complete_context: annotations->{origin} is correct');
}

# Test 17: position is set to $pos
{
    my $value = Chalk::Bootstrap::Context->new(focus => 'leaf');
    my $ctx = $parser->_make_complete_context($value, 'Expression', 0, 4, 1);
    is($ctx->position(), 4,
        '_make_complete_context: position is set to $pos');
}

# -------------------------------------------------------------------------
# Hash-consing safety: annotated Contexts are always unique objects
# -------------------------------------------------------------------------

# Test 18: two scan contexts with same matched_text but different rule_names
#           have different refaddrs (no hash-consing across annotations)
{
    my $ctx1 = $parser->_make_scan_context('foo', 'Rule1', 0, 0);
    my $ctx2 = $parser->_make_scan_context('foo', 'Rule2', 0, 0);
    isnt(refaddr($ctx1), refaddr($ctx2),
        'different rule_names produce distinct scan Context objects');
}

# Test 19: two complete contexts with same value but different rule_names
#           have different refaddrs
{
    my $value = Chalk::Bootstrap::Context->new(focus => 'leaf');
    my $ctx1 = $parser->_make_complete_context($value, 'Rule1', 0, 4, 1);
    my $ctx2 = $parser->_make_complete_context($value, 'Rule2', 0, 4, 1);
    isnt(refaddr($ctx1), refaddr($ctx2),
        'different rule_names produce distinct complete Context objects');
}

# Test 20: annotation values are accessible via ->annotations()->{key}
{
    my $ctx = $parser->_make_scan_context('tok', 'MyRule', 3, 7);
    my $ann = $ctx->annotations();
    is(ref($ann), 'HASH', 'annotations() returns a hashref');
    ok(exists $ann->{scan},       'annotations hashref has scan key');
    ok(exists $ann->{rule_name},  'annotations hashref has rule_name key');
    ok(exists $ann->{alt_idx},    'annotations hashref has alt_idx key');
    ok(exists $ann->{predicted},  'annotations hashref has predicted key');
}

done_testing();
