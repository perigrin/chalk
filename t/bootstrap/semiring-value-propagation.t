# ABOUTME: Verifies that semiring callbacks receive correct accumulated values.
# ABOUTME: Instruments a semiring to trace every multiply/complete callback and validates parse history.
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
# TracingSemiring: records multiply and complete callbacks
#
# With the unified multiply protocol, scan events arrive as:
#   multiply($value, $scan_ctx) where $scan_ctx->annotations->{scan} is true
#
# The semiring detects scan Contexts by checking annotations->{scan} on the
# right argument, logs them as 'scan' events, and returns a structured result
# that captures the accumulated history depth.
# ============================================================

package TracingSemiring {
    use 5.42.0;
    use utf8;

    sub new ($class) {
        return bless { log => [], one_val => { tag => 'one', depth => 0 } }, $class;
    }

    sub log ($self) { return $self->{log} }
    sub clear_log ($self) { $self->{log} = [] }
    sub slot_name ($self) { return undef }  # SA position — receives full Context

    sub _log ($self, $event, $info) {
        push $self->{log}->@*, { event => $event, %$info };
    }

    sub zero ($self) { return undef }
    sub one ($self) { return $self->{one_val} }
    sub is_zero ($self, $value) { return !defined $value }
    sub reset_cache ($self) { }

    # Extract raw hashref from a value that may be a Context (from FilterComposite)
    sub _raw ($self, $value) {
        return undef unless defined $value;
        if (blessed($value) && $value->can('extract')) {
            my $focus = $value->extract();
            # Return the focus if it is a hashref (structured result)
            return $focus if ref($focus) eq 'HASH';
            # For scan Contexts the focus is the matched text string.
            # Return a synthetic tag hash so callers can read -{tag} safely.
            return { tag => "scan_leaf:$focus", depth => 0 } if defined $focus;
            return undef;
        }
        return $value;
    }

    # Compute depth of a structured tag-hash result tree.
    sub _depth ($val, $seen = {}) {
        return 0 unless defined $val && ref($val) eq 'HASH';
        my $addr = refaddr($val);
        return 0 if exists $seen->{$addr};
        $seen->{$addr} = 1;
        return $val->{depth} if exists $val->{depth};
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

    # multiply: combines two values in sequence.
    # Detects scan events by checking annotations->{scan} on the right argument.
    # Scan events: right is an annotated scan Context from Earley._make_scan_context.
    sub multiply ($self, $left, $right) {
        return undef if !defined $left || !defined $right;
        my $l_raw = $self->_raw($left);
        my $l_depth = defined $l_raw ? (_depth($l_raw) // 0) : 0;
        my $l_tag   = defined $l_raw ? ($l_raw->{tag} // '?') : 'ZERO';

        # Detect scan Context: right has annotations->{scan} = true
        if (blessed($right) && $right->can('annotations')
                && $right->annotations()->{scan}) {
            my $matched_text = $right->focus() // '';
            my $rule_name    = $right->annotations()->{rule_name} // '';
            $self->_log('scan', {
                rule      => $rule_name,
                text      => $matched_text,
                value_tag => $l_tag,
                depth     => $l_depth,
            });
            my $result = { tag => "scan:$rule_name:$matched_text",
                           depth => $l_depth + 1 };
            return $result;
        }

        my $r_raw   = $self->_raw($right);
        my $r_depth = defined $r_raw ? (_depth($r_raw) // 0) : 0;
        my $result  = { tag => 'mul',
                        depth => ($l_depth > $r_depth ? $l_depth : $r_depth) + 1,
                        children => [$l_raw, $r_raw] };
        $self->_log('multiply', {
            left_tag  => $l_tag,
            right_tag => defined $r_raw ? ($r_raw->{tag} // '?') : 'ZERO',
        });
        return $result;
    }

    sub add ($self, $left, $right) {
        return [$right] if !defined $left;
        return [$left]  if !defined $right;
        my $l_raw = $self->_raw($left);
        my $r_raw = $self->_raw($right);
        $self->_log('add', {
            left_tag  => defined $l_raw ? ($l_raw->{tag} // '?') : 'ZERO',
            right_tag => defined $r_raw ? ($r_raw->{tag} // '?') : 'ZERO',
        });
        return [$left];
    }

    sub on_complete ($self, $value, $rule_name, $alt_idx, $pos, $origin, $on_epoch_commit = undef) {
        return undef if !defined $value;
        my $raw = $self->_raw($value);
        my $depth = defined $raw ? _depth($raw) : 0;
        my $result = { tag => "complete:$rule_name", depth => $depth + 1, inner => $raw };
        $self->_log('on_complete', {
            rule      => $rule_name,
            pos       => $pos,
            origin    => $origin,
            value_tag => defined $raw ? ($raw->{tag} // '?') : 'ZERO',
            depth     => $depth,
        });
        return $result;
    }
}

# ============================================================
# Test 1: Simple two-terminal rule — A ::= /x/ /y/
# ============================================================

subtest 'two terminals: multiply called for each scan' => sub {
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

    # Scan for /x/: the left value carries one (rule start), depth=0
    my @x_scans = grep { $_->{event} eq 'scan' && $_->{text} eq 'x' } @log;
    ok(scalar @x_scans >= 1, 'scan logged for x');
    is($x_scans[0]->{value_tag}, 'one', 'x scan: left value is one (rule start)');
    is($x_scans[0]->{depth}, 0, 'x scan: left depth is 0');

    # Scan for /y/: the left value has depth > 0 (contains x scan result)
    my @y_scans = grep { $_->{event} eq 'scan' && $_->{text} eq 'y' } @log;
    ok(scalar @y_scans >= 1, 'scan logged for y');
    ok($y_scans[0]->{depth} > 0, 'y scan: left value has depth (contains x history)')
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
# The + scan must see first E's completion in accumulated left value
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

    # scan for +: the left value must have depth > 0 (first E completed)
    my @plus_scans = grep { $_->{event} eq 'scan' && $_->{text} eq '+' } @log;
    ok(scalar @plus_scans >= 1, 'scan logged for +');
    ok($plus_scans[0]->{depth} > 0,
        '+ scan: left value has depth (first E in history)')
        or diag("+ depth=$plus_scans[0]->{depth} tag=$plus_scans[0]->{value_tag}");

    # S completes with full tree
    my @s_comp = grep { $_->{event} eq 'on_complete' && $_->{rule} eq 'S' } @log;
    ok(scalar @s_comp >= 1, 'S completes');
    ok($s_comp[0]->{depth} > 2, 'S on_complete: full tree depth')
        or diag("S depth=$s_comp[0]->{depth}");
};

done_testing();
