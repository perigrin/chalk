# ABOUTME: Verifies Leo-enabled and Leo-disabled parses produce isomorphic Context graphs.
# ABOUTME: Uses canonical post-order hashing to test graph equivalence structure-first.
use 5.42.0;
use utf8;
use Test::More;
use Digest::SHA qw(sha1_hex);
use Scalar::Util qw(refaddr blessed);

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Context;

# --------------------------------------------------------------------
# Canonical hash: content-based post-order hash of a Context graph.
# Two Contexts with isomorphic graphs (same labels, same child order,
# same annotations) produce the same hash. Different refaddrs don't
# matter — content only.
# --------------------------------------------------------------------
sub canonical_hash ($ctx) {
    return 'UNDEF' unless defined $ctx;

    # Scalar value: hash its stringification
    if (!ref $ctx) {
        return 'SCALAR:' . sha1_hex("$ctx");
    }

    # Not a Context (e.g., IR node, arrayref) — stringify with class
    if (!blessed($ctx) || !$ctx->isa('Chalk::Bootstrap::Context')) {
        my $class = ref($ctx) || '';
        return "OBJ:$class:" . sha1_hex(_stringify_deep($ctx));
    }

    my $focus_hash = canonical_hash($ctx->extract);
    my $rule       = $ctx->rule // '';
    my @child_hashes = map { canonical_hash($_) } $ctx->children->@*;
    my $annots_str = _canonical_json($ctx->annotations);

    return 'CTX:' . sha1_hex(
        "rule=$rule|focus=$focus_hash|annots=$annots_str|children=" . join(',', @child_hashes)
    );
}

# Canonicalize a hashref/arrayref/scalar to a deterministic string.
# Sorted keys at every level. Refs stringified with class.
sub _canonical_json ($val) {
    return 'null' unless defined $val;
    if (ref $val eq 'HASH') {
        my @pairs;
        for my $k (sort keys $val->%*) {
            push @pairs, "$k=" . _canonical_json($val->{$k});
        }
        return '{' . join(',', @pairs) . '}';
    }
    if (ref $val eq 'ARRAY') {
        return '[' . join(',', map { _canonical_json($_) } $val->@*) . ']';
    }
    if (ref $val) {
        # Blessed or other reference — stringify the type, not the address
        return 'REF:' . (blessed($val) || ref($val));
    }
    return "s:$val";
}

sub _stringify_deep ($val) {
    return _canonical_json($val);
}

# --------------------------------------------------------------------
# first_divergence: walk two Context trees in parallel, report the first
# structural or label difference. Returns a human-readable string, or
# undef if trees are equivalent.
# --------------------------------------------------------------------
sub first_divergence ($a, $b, $path = 'root') {
    if (!defined $a && !defined $b) { return undef }
    if (!defined $a || !defined $b) {
        return "$path: one side undef (a=" . (defined $a ? 'def' : 'undef') . ", b=" . (defined $b ? 'def' : 'undef') . ')';
    }

    if (!ref($a) || !ref($b)) {
        return "$path: scalar mismatch a='$a' b='$b'" if "$a" ne "$b";
        return undef;
    }

    if (!blessed($a) || !$a->isa('Chalk::Bootstrap::Context')) {
        # Non-Context ref — compare via canonical_json
        my $ja = _canonical_json($a);
        my $jb = _canonical_json($b);
        return "$path: non-Context mismatch a=$ja b=$jb" if $ja ne $jb;
        return undef;
    }

    my $ra = $a->rule // '';
    my $rb = $b->rule // '';
    return "$path: rule mismatch '$ra' vs '$rb'" if $ra ne $rb;

    my $fa = $a->extract;
    my $fb = $b->extract;
    if (my $d = first_divergence($fa, $fb, "$path/focus")) {
        return $d;
    }

    my $ka = _canonical_json($a->annotations);
    my $kb = _canonical_json($b->annotations);
    if ($ka ne $kb) {
        return "$path: annotations mismatch a=$ka b=$kb";
    }

    my @ca = $a->children->@*;
    my @cb = $b->children->@*;
    if (@ca != @cb) {
        return "$path: child count mismatch a=" . scalar(@ca) . " b=" . scalar(@cb)
             . " rule=$ra";
    }
    for my $i (0 .. $#ca) {
        if (my $d = first_divergence($ca[$i], $cb[$i], "$path/child[$i]")) {
            return $d;
        }
    }

    return undef;
}

# --------------------------------------------------------------------
# Grammar helpers
# --------------------------------------------------------------------
sub terminal ($v) {
    return Chalk::Grammar::Symbol->new(type => 'terminal', value => $v);
}
sub reference ($v) {
    return Chalk::Grammar::Symbol->new(type => 'reference', value => $v);
}
sub rule ($name, @alternatives) {
    return Chalk::Grammar::Rule->new(name => $name, expressions => [@alternatives]);
}

# Parse input with Leo on AND off using the same grammar + fresh SA semirings.
# Returns the two Context results (from parse_value).
sub parse_both ($grammar, $input) {
    my $sr_on  = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $sr_off = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $p_on = Chalk::Bootstrap::Earley->new(
        grammar      => $grammar,
        semiring     => $sr_on,
        leo_enabled  => 1,
    );
    my $p_off = Chalk::Bootstrap::Earley->new(
        grammar      => $grammar,
        semiring     => $sr_off,
        leo_enabled  => 0,
    );
    return ($p_on->parse_value($input), $p_off->parse_value($input));
}

# --------------------------------------------------------------------
# Tier 1: Linear grammar (Leo inert)
# --------------------------------------------------------------------
subtest 'Tier 1: linear grammar (Leo inert)' => sub {
    my $grammar = [
        rule('Start', [reference('A'), reference('B'), reference('C')]),
        rule('A', [terminal('a')]),
        rule('B', [terminal('b')]),
        rule('C', [terminal('c')]),
    ];

    my $input = 'abc';
    my ($on, $off) = parse_both($grammar, $input);

    ok(defined $on,  "Leo-on:  parse succeeded ($input)");
    ok(defined $off, "Leo-off: parse succeeded ($input)");

    my $ha = canonical_hash($on);
    my $hb = canonical_hash($off);
    is($ha, $hb, "Tier 1 '$input': canonical hashes equal")
        or diag(first_divergence($on, $off) // '(no structural diff found, yet hashes differ)');
};

# --------------------------------------------------------------------
# Tier 2: Right-recursive Chain
# Chain ::= Item | Item Sep Chain
# Leo should fire on deterministic right-recursive completion chains.
# --------------------------------------------------------------------
subtest 'Tier 2: right-recursive Chain' => sub {
    my $grammar = [
        rule('Chain',
            [reference('Item')],
            [reference('Item'), reference('Sep'), reference('Chain')],
        ),
        rule('Item', [terminal('\w+')]),
        rule('Sep',  [terminal(',')]),
    ];

    for my $n (1, 2, 5, 10) {
        my $input = join ',', map { "x$_" } 1 .. $n;
        my ($on, $off) = parse_both($grammar, $input);

        ok(defined $on  && !$on->is_zero,  "Leo-on:  parse succeeded (n=$n)");
        ok(defined $off && !$off->is_zero, "Leo-off: parse succeeded (n=$n)");

        my $ha = canonical_hash($on);
        my $hb = canonical_hash($off);
        is($ha, $hb, "Tier 2 n=$n: canonical hashes equal")
            or diag(first_divergence($on, $off) // '(hashes differ but no structural diff found)');
    }
};

# --------------------------------------------------------------------
# Tier 3: Left-recursive List
# List ::= Item | List Sep Item
# --------------------------------------------------------------------
subtest 'Tier 3: left-recursive List' => sub {
    my $grammar = [
        rule('List',
            [reference('Item')],
            [reference('List'), reference('Sep'), reference('Item')],
        ),
        rule('Item', [terminal('\w+')]),
        rule('Sep',  [terminal(',')]),
    ];

    for my $n (1, 2, 5, 10) {
        my $input = join ',', map { "y$_" } 1 .. $n;
        my ($on, $off) = parse_both($grammar, $input);

        ok(defined $on  && !$on->is_zero,  "Leo-on:  parse succeeded (n=$n)");
        ok(defined $off && !$off->is_zero, "Leo-off: parse succeeded (n=$n)");

        my $ha = canonical_hash($on);
        my $hb = canonical_hash($off);
        is($ha, $hb, "Tier 3 n=$n: canonical hashes equal")
            or diag(first_divergence($on, $off) // '(hashes differ but no structural diff found)');
    }
};

done_testing();
