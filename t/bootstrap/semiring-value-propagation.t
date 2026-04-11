# ABOUTME: Verifies that semiring callbacks receive correct accumulated values.
# ABOUTME: Instruments a semiring to trace every callback and validates the parse history contract.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::FilterComposite;

# ============================================================
# Helpers for building grammars
# ============================================================

sub terminal ($value) {
    return Chalk::Grammar::Symbol->new(type => 'terminal', value => $value);
}

sub reference ($value) {
    return Chalk::Grammar::Symbol->new(type => 'reference', value => $value);
}

# ============================================================
# TracingSemiring: records every callback with its arguments
# ============================================================

package TracingSemiring {
    use 5.42.0;
    use utf8;

    sub new ($class) {
        return bless { log => [], one_val => { tag => 'one' } }, $class;
    }

    sub log ($self) { return $self->{log} }
    sub clear_log ($self) { $self->{log} = [] }

    sub _log ($self, $event, $info) {
        push $self->{log}->@*, { event => $event, %$info };
    }

    sub zero ($self) { return undef }
    sub one ($self) { return $self->{one_val} }
    sub is_zero ($self, $value) { return !defined $value }
    sub reset_cache ($self) { }

    sub multiply ($self, $left, $right) {
        return undef if !defined $left || !defined $right;
        my $result = { tag => 'mul', children => [$left, $right] };
        $self->_log('multiply', {
            left_tag  => $left->{tag} // '?',
            right_tag => $right->{tag} // '?',
        });
        return $result;
    }

    sub add ($self, $left, $right) {
        return [$right] if !defined $left;
        return [$left]  if !defined $right;
        $self->_log('add', {
            left_tag  => $left->{tag} // '?',
            right_tag => $right->{tag} // '?',
        });
        return [$left];
    }

    sub on_scan ($self, $value, $rule_name, $alt_idx, $pos, $matched_text) {
        return undef if !defined $value;
        my $scan_val = { tag => "scan:$rule_name:$matched_text" };
        $self->_log('on_scan', {
            rule      => $rule_name,
            pos       => $pos,
            text      => $matched_text,
            value_tag => $value->{tag} // '?',
            depth     => _depth($value),
        });
        return $self->multiply($value, $scan_val);
    }

    sub should_scan ($self, $value, $rule_name, $alt_idx, $pos, $matched_text, $is_predicted) {
        $self->_log('should_scan', {
            rule      => $rule_name,
            pos       => $pos,
            text      => $matched_text,
            value_tag => defined $value ? ($value->{tag} // '?') : 'ZERO',
            depth     => defined $value ? _depth($value) : 0,
        });
        return true;
    }

    sub on_complete ($self, $value, $rule_name, $alt_idx, $pos, $origin, $on_epoch_commit = undef) {
        return undef if !defined $value;
        my $result = { tag => "complete:$rule_name", inner => $value };
        $self->_log('on_complete', {
            rule      => $rule_name,
            pos       => $pos,
            origin    => $origin,
            value_tag => $value->{tag} // '?',
            depth     => _depth($value),
        });
        return $result;
    }

    # Measure depth of value tree
    sub _depth ($val, $seen = {}) {
        return 0 unless defined $val && ref($val) eq 'HASH';
        my $addr = refaddr($val);
        return 0 if exists $seen->{$addr};
        $seen->{$addr} = 1;
        my $max = 0;
        for my $key (qw(children inner)) {
            next unless exists $val->{$key};
            my $child = $val->{$key};
            if (ref($child) eq 'ARRAY') {
                for my $c ($child->@*) {
                    my $d = _depth($c, $seen);
                    $max = $d if $d > $max;
                }
            } elsif (ref($child) eq 'HASH') {
                my $d = _depth($child, $seen);
                $max = $d if $d > $max;
            }
        }
        return $max + 1;
    }

    # Walk tree to find a tag value
    sub find_tag ($val, $tag_name, $seen = {}) {
        return unless defined $val && ref($val) eq 'HASH';
        my $addr = refaddr($val);
        return if exists $seen->{$addr};
        $seen->{$addr} = 1;
        return $val->{tag} if ($val->{tag} // '') =~ /^\Q$tag_name\E/;
        for my $key (qw(children inner)) {
            next unless exists $val->{$key};
            my $child = $val->{$key};
            if (ref($child) eq 'ARRAY') {
                for my $c ($child->@*) {
                    my $found = find_tag($c, $tag_name, $seen);
                    return $found if defined $found;
                }
            } elsif (ref($child) eq 'HASH') {
                my $found = find_tag($child, $tag_name, $seen);
                return $found if defined $found;
            }
        }
        return;
    }
}

# ============================================================
# Test 1: Simple two-terminal rule — A ::= /x/ /y/
# ============================================================

subtest 'two terminals: on_scan receives accumulated history' => sub {
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[terminal('x'), terminal('y')]],
        ),
    ];

    my $bool = Chalk::Bootstrap::Semiring::Boolean->new();
    my $tracer = TracingSemiring->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool, $tracer],
    );
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $comp,
    );

    $tracer->clear_log();
    my $result = $parser->parse_value("xy");
    ok(defined $result, 'parse succeeds');

    my @log = $tracer->log()->@*;

    # on_scan for /x/: value should be one (start of rule)
    my @x_scans = grep { $_->{event} eq 'on_scan' && $_->{text} eq 'x' } @log;
    ok(scalar @x_scans >= 1, 'on_scan called for x');
    is($x_scans[0]->{value_tag}, 'one', 'x on_scan: value is one (rule start)');

    # on_scan for /y/: value should have depth > 1 (contains x scan result)
    my @y_scans = grep { $_->{event} eq 'on_scan' && $_->{text} eq 'y' } @log;
    ok(scalar @y_scans >= 1, 'on_scan called for y');
    ok($y_scans[0]->{depth} > 0, 'y on_scan: value has depth (contains x history)')
        or diag("y depth=$y_scans[0]->{depth} tag=$y_scans[0]->{value_tag}");

    # on_complete for A: value should have depth > 1 (contains both scans)
    my @a_comp = grep { $_->{event} eq 'on_complete' && $_->{rule} eq 'A' } @log;
    ok(scalar @a_comp >= 1, 'on_complete called for A');
    ok($a_comp[0]->{depth} > 1, 'A on_complete: value has depth > 1 (both scans)')
        or diag("A depth=$a_comp[0]->{depth} tag=$a_comp[0]->{value_tag}");
};

# ============================================================
# Test 2: Nested rule — A ::= B ; B ::= /x/ /y/
# Completion values must propagate across rule boundaries
# ============================================================

subtest 'nested rule: completion propagates across boundaries' => sub {
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[reference('B')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('x'), terminal('y')]],
        ),
    ];

    my $bool = Chalk::Bootstrap::Semiring::Boolean->new();
    my $tracer = TracingSemiring->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool, $tracer],
    );
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $comp,
    );

    $tracer->clear_log();
    my $result = $parser->parse_value("xy");
    ok(defined $result, 'parse succeeds');

    my @log = $tracer->log()->@*;

    # B completes with depth from both scans
    my @b_comp = grep { $_->{event} eq 'on_complete' && $_->{rule} eq 'B' } @log;
    ok(scalar @b_comp >= 1, 'B completes');
    ok($b_comp[0]->{depth} > 1, 'B on_complete: has scan history');

    # A completes and its value includes B's completion
    my @a_comp = grep { $_->{event} eq 'on_complete' && $_->{rule} eq 'A' } @log;
    ok(scalar @a_comp >= 1, 'A completes');
    ok($a_comp[0]->{depth} > $b_comp[0]->{depth},
        'A on_complete: deeper than B (wraps B completion)')
        or diag("A=$a_comp[0]->{depth} B=$b_comp[0]->{depth}");
};

# ============================================================
# Test 3: Binary pattern — S ::= E /[+]/ E ; E ::= /\w+/
# The + scan and second E scan must see first E's completion
# ============================================================

subtest 'binary: operator scan sees left operand history' => sub {
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'S',
            expressions => [[reference('E'), terminal('[+]'), reference('E')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'E',
            expressions => [[terminal('\\w+')]],
        ),
    ];

    my $bool = Chalk::Bootstrap::Semiring::Boolean->new();
    my $tracer = TracingSemiring->new();
    my $comp = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool, $tracer],
    );
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $comp,
    );

    $tracer->clear_log();
    my $result = $parser->parse_value("a+b");
    ok(defined $result, 'parse succeeds');

    my @log = $tracer->log()->@*;

    # should_scan for +: value must have depth > 0 (first E completed)
    my @plus_ss = grep { $_->{event} eq 'should_scan' && $_->{text} eq '+' } @log;
    ok(scalar @plus_ss >= 1, 'should_scan called for +');
    ok($plus_ss[0]->{depth} > 0,
        '+ should_scan: value has depth (first E in history)')
        or diag("+ depth=$plus_ss[0]->{depth} tag=$plus_ss[0]->{value_tag}");

    # on_scan for +: same check
    my @plus_os = grep { $_->{event} eq 'on_scan' && $_->{text} eq '+' } @log;
    ok(scalar @plus_os >= 1, 'on_scan called for +');
    ok($plus_os[0]->{depth} > 0,
        '+ on_scan: value has depth (first E in history)')
        or diag("+ depth=$plus_os[0]->{depth} tag=$plus_os[0]->{value_tag}");

    # S completes with full tree
    my @s_comp = grep { $_->{event} eq 'on_complete' && $_->{rule} eq 'S' } @log;
    ok(scalar @s_comp >= 1, 'S completes');
    ok($s_comp[0]->{depth} > 2, 'S on_complete: full tree depth')
        or diag("S depth=$s_comp[0]->{depth}");
};

done_testing();
