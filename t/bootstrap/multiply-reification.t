# ABOUTME: Tests for Earley annotation helpers that reify scan/complete events as Context objects.
# ABOUTME: Issue #710 — first component of on_complete elimination via multiply reification.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Context;

sub terminal($value) {
    return Chalk::Grammar::Symbol->new(type => 'terminal', value => $value);
}

sub reference($value) {
    return Chalk::Grammar::Symbol->new(type => 'reference', value => $value);
}

# Minimal grammar so we can construct an Earley instance
sub make_earley() {
    my @grammar = (
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('a')]],
        ),
    );
    return Chalk::Bootstrap::Earley->new(
        grammar  => \@grammar,
        semiring => Chalk::Bootstrap::Semiring::Boolean->new(),
    );
}

# Task 1: Scan annotation helper
{
    my $earley = make_earley();
    my $predicted = { Start => 1, Atom => 1 };

    my $ctx = $earley->_make_scan_context('foo', 'Atom', 2, $predicted);

    isa_ok($ctx, 'Chalk::Bootstrap::Context', 'scan context is a Context');
    is($ctx->extract, 'foo', 'focus is the matched text');

    my $ann = $ctx->annotations;
    is($ann->{rule_name}, 'Atom', 'annotations has rule_name');
    is($ann->{alt_idx},   2,      'annotations has alt_idx');
    is($ann->{matched_text}, 'foo', 'annotations has matched_text');
    is_deeply(
        $ann->{predicted},
        { Start => 1, Atom => 1 },
        'annotations has predicted set',
    );
}

# Task 2: Complete annotation helper
{
    my $earley = make_earley();
    my $ir_value = { kind => 'IRNode', name => 'Block' };

    my $ctx = $earley->_make_complete_context($ir_value, 'Block', 0, 7, 3);

    isa_ok($ctx, 'Chalk::Bootstrap::Context', 'complete context is a Context');
    is($ctx->extract, $ir_value, 'focus is the completed value');

    my $ann = $ctx->annotations;
    is($ann->{rule_name}, 'Block', 'annotations has rule_name');
    is($ann->{alt_idx},   0,       'annotations has alt_idx');
    is($ann->{pos},       7,       'annotations has pos');
    is($ann->{origin},    3,       'annotations has origin');
}

# Task 3: Hash-consing uniqueness — same value, different rule_names
{
    my $earley = make_earley();
    my $value = 'shared';

    my $ctx_a = $earley->_make_scan_context($value, 'RuleA', 0, {});
    my $ctx_b = $earley->_make_scan_context($value, 'RuleB', 0, {});

    isnt(
        refaddr($ctx_a), refaddr($ctx_b),
        'different rule_names produce different refaddrs (hash-consing safe)',
    );
    is($ctx_a->extract, $ctx_b->extract,
        'same value is preserved across both contexts');
    isnt(
        $ctx_a->annotations->{rule_name},
        $ctx_b->annotations->{rule_name},
        'rule_names differ in annotations',
    );
}

# Also verify complete contexts differ by rule_name
{
    my $earley = make_earley();
    my $value = 'shared';

    my $ctx_a = $earley->_make_complete_context($value, 'RuleA', 0, 1, 0);
    my $ctx_b = $earley->_make_complete_context($value, 'RuleB', 0, 1, 0);

    isnt(
        refaddr($ctx_a), refaddr($ctx_b),
        'complete contexts with different rule_names have different refaddrs',
    );
}

done_testing();
