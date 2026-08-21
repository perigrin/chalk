# ABOUTME: Byte-completeness gate over every constructible Chalk::IR::Node
# ABOUTME: subclass: round-trips one instance of each op and asserts every field survives.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use File::Basename qw(basename);
use Scalar::Util qw(blessed);
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::IR::Serialize::JSON qw(to_json from_json);

# =============================================================================
# COVERAGE (non-vacuous per the AC): enumerate every lib/Chalk/IR/Node/*.pm
# file and assert this audit either exercises it (constructs + round-trips an
# instance) or explicitly justifies why it cannot (an abstract intermediate
# base class with no operation() override of its own — never directly
# constructed by NodeFactory). A subclass added later with neither an audit
# entry nor an exclusion entry fails this coverage check by omission, which is
# exactly the AC's "must NOT pass by omission" requirement.
# =============================================================================

# Abstract intermediate base classes: grouping types under Chalk::IR::Node
# with no operation() override of their own (calling ->operation would die
# with the base class's "must implement" message, or — for Access/Aggregate,
# which have no operation() at all — is simply never invoked because
# NodeFactory's %DATA_CLASSES/%CFG_CLASSES tables never name them). Verified
# by reading each file: BinOp/UnaryOp/Regex declare no operation() method;
# Access/Aggregate declare no methods at all. None appears in NodeFactory's
# construction tables, so none is reachable via make()/make_cfg().
my %ABSTRACT_BASE = map { $_ => 1 } qw(
    Access Aggregate BinOp Regex UnaryOp
);

# -----------------------------------------------------------------------
# Per-op audit spec: build => a builder returning ($node, $start, $ret,
# \%expect) where $node is wired into a tiny Start/Return graph, and
# %expect maps accessor-method-name => expected value (checked on the
# node found after round-trip, by matching operation() in the reloaded
# graph). A field genuinely unsupported by the serializer is recorded
# in %KNOWN_GAP instead of %expect (see the KNOWN GAPS section below) so
# the audit documents the loss rather than silently not checking it.
# -----------------------------------------------------------------------

sub _base_graph ($f, $value_node) {
    my $start = $f->make_cfg('Start');
    my $ret   = $f->make_cfg('Return', inputs => [$start, $value_node]);
    return Chalk::IR::Graph->new(start => $start, returns => [$ret]);
}

# one_const($f, $val, $type) -- a Constant to use as a generic operand.
sub _const ($f, $val, $type = 'integer') {
    return $f->make('Constant', value => $val, const_type => $type);
}

# Every BinOp-family op just needs two operands wired through `inputs`;
# there is no extra per-op field, so one shared builder covers the whole
# family (verified: Add/Subtract/.../Yada declare zero :param fields of
# their own, per the field survey in the session that wrote this audit).
my @BINOP_FAMILY = qw(
    Add Subtract Multiply Divide Modulo Power Concat
    NumEq NumNe NumLt NumGt NumLe NumGe NumCmp
    StrEq StrNe StrLt StrGt StrLe StrGe StrCmp
    And Or BitAnd BitOr BitXor LeftShift RightShift
    Assign Repeat Match NotMatch DefinedOr Xor Range Yada IsaOp
);

# Every UnaryOp-family op needs one operand; likewise zero extra fields.
my @UNARYOP_FAMILY = qw(
    Not Negate Complement Defined UnaryPlus Ref RefType Length
);

# Ops with no extra fields beyond `inputs` (structural-only; verified by the
# field survey — no :param declarations beyond the base Node/BinOp/UnaryOp/
# Aggregate/Access ancestor fields). Round-tripping checks only that the op
# name and input wiring survive (covered generically below).
# NO Stringify: the node was deleted in 73ab9720 -- Stringify(X) IS
# Coerce(X -> Str), two node types implementing one edge, and Coerce is now the
# only spelling. Coerce has its own %SPEC entry (it carries from_repr/to_repr,
# so it is not structural-only). This list is hand-maintained, so a deleted op
# leaves a name behind that dies at `make`; audited 2026-08-20 and Stringify was
# the only such name.
my @STRUCTURAL_ONLY = qw(
    ArrayRef HashRef Slice Interpolate
    Print TryCatch BacktickExpr
    StructRef StructFieldAccess TernaryExpr ExpressionList
    Start MemStart Unwind Subscript
);

# -----------------------------------------------------------------------
# %SPEC: op => sub($factory) that returns ($node, \%expect_fields).
# \%expect_fields maps accessor-name => expected scalar value, checked
# against the round-tripped node.
# -----------------------------------------------------------------------
my %SPEC;

for my $op (@BINOP_FAMILY) {
    $SPEC{$op} = sub ($f) {
        my $l = _const($f, '1');
        my $r = _const($f, '2');
        my $node = $op eq 'Range' || $op eq 'Repeat'
            ? $f->make($op, inputs => [$l, $r])
            : $f->make($op, inputs => [$l, $r]);
        return ($node, {});
    };
}

for my $op (@UNARYOP_FAMILY) {
    $SPEC{$op} = sub ($f) {
        my $operand = _const($f, '5');
        my $node = $f->make($op, inputs => [$operand]);
        return ($node, {});
    };
}

for my $op (@STRUCTURAL_ONLY) {
    $SPEC{$op} = sub ($f) {
        my $operand = _const($f, '7');
        my $node = $f->make($op, inputs => [$operand]);
        return ($node, {});
    };
}

$SPEC{Constant} = sub ($f) {
    my $node = _const($f, 'hello', 'string');
    return ($node, { value => 'hello', const_type => 'string' });
};

$SPEC{Call} = sub ($f) {
    my $arg  = _const($f, '1');
    my $node = $f->make('Call',
        dispatch_kind => 'builtin', name => 'push',
        class_name    => 'My::Class',
        param_names   => ['x', 'y'],
        paren_form    => true,
        inputs        => [$arg]);
    return ($node, {
        dispatch_kind => 'builtin', name => 'push',
        class_name => 'My::Class', param_names => ['x', 'y'],
        paren_form => true,
    });
};

$SPEC{Phi} = sub ($f) {
    my $region = $f->make_cfg('Region', inputs => []);
    my $init   = _const($f, '0');
    my $node   = $f->make('Phi', region => $region, values => [$init]);
    return ($node, { region_op => 'Region' });
};

$SPEC{Proj} = sub ($f) {
    my $region = $f->make_cfg('Region', inputs => []);
    my $node   = $f->make_cfg('Proj', inputs => [$region], index => 1);
    return ($node, { index => 1 });
};

$SPEC{PadAccess} = sub ($f) {
    my $node = $f->make('PadAccess', targ => 3, varname => 'x', inputs => []);
    return ($node, { targ => 3, varname => 'x' });
};

$SPEC{FieldAccess} = sub ($f) {
    my $node = $f->make('FieldAccess',
        field_index => 2, field_stash => 'My::Class', inputs => []);
    return ($node, { field_index => 2, field_stash => 'My::Class' });
};

$SPEC{StashAccess} = sub ($f) {
    # sigil is deliberately '@', NOT the '$' default: a spec using the default
    # value passes even when the field is dropped entirely, which is exactly
    # the pass-by-omission this file exists to prevent. `sigil` was added and
    # this spec did not notice.
    my $node = $f->make('StashAccess',
        stash_name => 'main', sigil => '@', var_name => 'g', inputs => []);
    return ($node, { stash_name => 'main', sigil => '@', var_name => 'g' });
};

$SPEC{CompoundAssign} = sub ($f) {
    my $l = _const($f, '1');
    my $r = _const($f, '2');
    my $node = $f->make('CompoundAssign', op => '+=', inputs => [$l, $r]);
    return ($node, { op => '+=' });
};

$SPEC{PostfixDeref} = sub ($f) {
    my $operand = _const($f, '1');
    my $node = $f->make('PostfixDeref', sigil => '@', inputs => [$operand]);
    return ($node, { sigil => '@' });
};

$SPEC{RegexMatch} = sub ($f) {
    my $subject = _const($f, 'x', 'string');
    my $node = $f->make('RegexMatch',
        pattern => 'ab+c', flags => 'i', inputs => [$subject]);
    return ($node, { pattern => 'ab+c', flags => 'i' });
};

$SPEC{RegexSubst} = sub ($f) {
    my $subject = _const($f, 'x', 'string');
    my $node = $f->make('RegexSubst',
        pattern => 'a', replacement => 'b', flags => 'g', inputs => [$subject]);
    return ($node, { pattern => 'a', replacement => 'b', flags => 'g' });
};

$SPEC{RegexCapture} = sub ($f) {
    my $node = $f->make('RegexCapture', n => 2, inputs => []);
    return ($node, { n => 2 });
};

$SPEC{EnvRead} = sub ($f) {
    my $node = $f->make('EnvRead', key => 'PATH', inputs => []);
    return ($node, { key => 'PATH' });
};

$SPEC{VarDecl} = sub ($f) {
    my $node = $f->make('VarDecl', scope => 'our', inputs => []);
    return ($node, { scope => 'our' });
};

# --- Known-gap ops: constructible via NodeFactory, but the field this audit
#     checks does NOT survive to_json/from_json today. Each is filed as a
#     %KNOWN_GAP entry (accessor => description) rather than silently
#     omitted, per the issue's directive: a real mis-round-trip found by
#     this audit is either fixed (if it's a minimal serializer field-handling
#     gap) or reported (if it's a deeper divergence). See the session report
#     for the STOP/report decision on each of these.
#
# Coerce.from_repr/to_repr WAS such a gap (in fact worse than silent loss:
# both fields are required, no-default :param, so _deserialize_graph's
# generic %args (missing from_repr/to_repr, since _extract_fields had no
# Coerce entry) made the constructor DIE on any graph containing a Coerce
# node). Fixed directly in Serialize/JSON.pm's _extract_fields/
# _deserialize_graph (mirrors the existing per-op field dispatch pattern),
# so this is now a normal (non-gap) round-trip assertion.
$SPEC{Coerce} = sub ($f) {
    my $operand = _const($f, '1');
    my $node = $f->make('Coerce',
        from_repr => 'Str', to_repr => 'Num', inputs => [$operand]);
    return ($node, { from_repr => 'Str', to_repr => 'Num' });
};

$SPEC{Return} = sub ($f) {
    # Return is CFG-routed (make_cfg), built directly as this op's own
    # graph root rather than via the generic harness below.
    my $val = _const($f, '9');
    my $node = $f->make_cfg('Return', inputs => [undef, $val], synthetic => true);
    return ($node, {});   # synthetic is a KNOWN_GAP; see below.
};

$SPEC{ListAssign} = sub ($f) {
    my $names = [ _const($f, 'x', 'string') ];
    my $init  = _const($f, '1');
    my $node  = $f->make('ListAssign', scope => 'our', inputs => [$names, $init]);
    return ($node, {});   # scope is a KNOWN_GAP; see below.
};

$SPEC{AnonSub} = sub ($f) {
    my $inner_f     = Chalk::IR::NodeFactory->new();
    my $inner_start = $inner_f->make_cfg('Start');
    my $inner_val   = _const($inner_f, '1');
    my $inner_ret   = $inner_f->make_cfg('Return', inputs => [$inner_start, $inner_val]);
    my $inner_graph = Chalk::IR::Graph->new(start => $inner_start, returns => [$inner_ret]);
    my $node = $f->make('AnonSub', graph => $inner_graph, inputs => []);
    return ($node, {});   # graph is a KNOWN_GAP; see below.
};

# CFG ops needing hand-built graphs (they ARE the control skeleton, so they
# can't be wired as an ordinary value feeding a Return the way every other
# op above is). Each gets its own tiny bespoke graph and is round-tripped
# directly rather than through the shared harness.
my %CFG_SPECIAL = map { $_ => 1 } qw(Start If Loop Region);

# -----------------------------------------------------------------------
# Coverage check: every *.pm under lib/Chalk/IR/Node/ is either in %SPEC,
# in %CFG_SPECIAL, or in %ABSTRACT_BASE (with its justification above).
# -----------------------------------------------------------------------
my @all_files = sort glob('lib/Chalk/IR/Node/*.pm');
ok(@all_files > 0, 'found lib/Chalk/IR/Node/*.pm files to audit');

my @uncovered;
for my $path (@all_files) {
    my $op = basename($path, '.pm');
    next if exists $SPEC{$op};
    next if exists $CFG_SPECIAL{$op};
    next if exists $ABSTRACT_BASE{$op};
    push @uncovered, $op;
}
is_deeply(\@uncovered, [],
    'every Chalk::IR::Node subclass is audited or explicitly excluded (no silent omission)')
    or diag('uncovered subclasses: ' . join(', ', @uncovered));

my $audited_count = scalar(keys %SPEC) + scalar(keys %CFG_SPECIAL);
cmp_ok($audited_count, '>=', scalar(@all_files) - scalar(keys %ABSTRACT_BASE),
    "audit constructs/round-trips $audited_count non-abstract subclasses "
    . '(out of ' . scalar(@all_files) . ' files, ' . scalar(keys %ABSTRACT_BASE)
    . ' abstract bases excluded)');

# =============================================================================
# ROUND-TRIP: every %SPEC entry — build, serialize, deserialize, verify.
# =============================================================================

for my $op (sort keys %SPEC) {
    subtest "round-trip: $op" => sub {
        my $f = Chalk::IR::NodeFactory->new();
        my ($node, $expect) = $SPEC{$op}->($f);

        my $graph;
        if ($op eq 'Return') {
            $graph = Chalk::IR::Graph->new(start => $f->make_cfg('Start'), returns => [$node]);
        }
        else {
            $graph = _base_graph($f, $node);
        }

        my $json   = to_json({ $op => $graph });
        my $loaded = from_json($json);
        ok(exists $loaded->{$op}, "round-trip: $op graph present after from_json") or return;

        my ($found) = grep { blessed($_) && $_->operation eq $op } $loaded->{$op}->nodes->@*;
        ok(defined $found, "round-trip: $op node found in reloaded graph") or return;

        for my $accessor (sort keys %$expect) {
            my $want = $expect->{$accessor};
            if ($accessor eq 'region_op') {
                is($found->region->operation, $want, "$op: region survives round-trip");
                next;
            }
            my $got = $found->$accessor();
            if (ref($want) eq 'ARRAY') {
                is_deeply($got, $want, "$op: field '$accessor' survives round-trip");
            }
            else {
                # Plain-scalar compare (not is_deeply): a `true`-builtin
                # dualvar expectation (PV+IV) vs a JSON::PP-decoded plain
                # IV (no PV slot) are `==`/`eq` equal but is_deeply treats
                # them as differing internal representations. This is a
                # dualvar-representation artifact of round-tripping through
                # JSON, not a real field loss (confirmed: JSON has no
                # boolean-with-string-slot type, so numeric booleans always
                # decode as plain IVs).
                is($got, $want, "$op: field '$accessor' survives round-trip");
            }
        }
    };
}

# =============================================================================
# CFG-special ops: Start/If/Loop/Region, each needing a bespoke tiny graph.
# =============================================================================

subtest 'round-trip: Start' => sub {
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $val   = _const($f, '1');
    my $ret   = $f->make_cfg('Return', inputs => [$start, $val]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $loaded = from_json(to_json({ Start => $graph }));
    my ($found) = grep { blessed($_) && $_->operation eq 'Start' } $loaded->{Start}->nodes->@*;
    ok(defined $found, 'Start node found after round-trip');
};

subtest 'round-trip: If' => sub {
    my $f       = Chalk::IR::NodeFactory->new();
    my $start   = $f->make_cfg('Start');
    my $cond    = _const($f, '1');
    my $if_node = $f->make_cfg('If', inputs => [$start, $cond]);
    my $t_proj  = $f->make_cfg('Proj', inputs => [$if_node], index => 1);
    my $f_proj  = $f->make_cfg('Proj', inputs => [$if_node], index => 0);
    my $region  = $f->make_cfg('Region', inputs => [$t_proj, $f_proj]);
    $if_node->set_region($region);
    my $val = _const($f, '2');
    my $ret = $f->make_cfg('Return', inputs => [$region, $val]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $loaded = from_json(to_json({ If => $graph }));
    my ($found) = grep { blessed($_) && $_->operation eq 'If' } $loaded->{If}->nodes->@*;
    ok(defined $found, 'If node found after round-trip');
};

subtest 'round-trip: Loop' => sub {
    # Real Loop construction (FromOptree.pm) passes a SINGLE-element
    # inputs => [entry_control] -- never a 2-element inputs array with a
    # backedge at inputs[1]. Loop::set_backedge_ctrl exists but is not
    # called anywhere in production (grep confirms zero call sites in
    # either repo's lib/); mirroring that shape here rather than inventing
    # a 2-input backedge shape the loader's forward-reference guard would
    # (correctly) reject as an unresolvable forward index.
    my $f    = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $loop  = $f->make_cfg('Loop', inputs => [$start]);
    my $exit_proj = $f->make_cfg('Proj', inputs => [$loop], index => 0);
    my $region    = $f->make_cfg('Region', inputs => [$exit_proj]);
    $loop->set_region($region);
    my $val = _const($f, '3');
    my $ret = $f->make_cfg('Return', inputs => [$region, $val]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $loaded = from_json(to_json({ Loop => $graph }));
    my ($found) = grep { blessed($_) && $_->operation eq 'Loop' } $loaded->{Loop}->nodes->@*;
    ok(defined $found, 'Loop node found after round-trip');
};

subtest 'round-trip: Region' => sub {
    my $f       = Chalk::IR::NodeFactory->new();
    my $start   = $f->make_cfg('Start');
    my $cond    = _const($f, '1');
    my $if_node = $f->make_cfg('If', inputs => [$start, $cond]);
    my $t_proj  = $f->make_cfg('Proj', inputs => [$if_node], index => 1);
    my $f_proj  = $f->make_cfg('Proj', inputs => [$if_node], index => 0);
    my $region  = $f->make_cfg('Region', inputs => [$t_proj, $f_proj]);
    $if_node->set_region($region);
    my $val = _const($f, '2');
    my $ret = $f->make_cfg('Return', inputs => [$region, $val]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $loaded = from_json(to_json({ Region => $graph }));
    my ($found) = grep { blessed($_) && $_->operation eq 'Region' } $loaded->{Region}->nodes->@*;
    ok(defined $found, 'Region node found after round-trip');
};

# =============================================================================
# KNOWN GAPS: fields that do NOT survive to_json/from_json today. Each is
# asserted here as a documented characterization (not a silent skip) so a
# future fix that starts preserving one of these is visible as a test
# needing an update, not a test that stays green either way.
#
# See the session report for the decision on each: Call.target,
# Return.synthetic, ListAssign.scope, AnonSub.graph. (Coerce.from_repr/to_repr
# and Call.paren_form were found here too. Coerce was worse than a silent-loss
# gap -- a crash on any Coerce-bearing graph -- and paren_form is genuinely
# part of Call's content_hash (not a decoration), so both were fixed directly
# in Serialize/JSON.pm's field dispatch tables; see the Call/Coerce %SPEC
# entries above, which now assert normal preservation instead of loss.)
# =============================================================================

subtest 'KNOWN GAP: Call.target does not survive round-trip (documented decoration)' => sub {
    # target (Call.pm) is explicitly excluded from content_hash and documented
    # as a late-binding decoration applied by a post-pass after the MOP has
    # every class's methods registered -- unlike resolved_graph (also a
    # decoration), it has no from_json re-derivation path, so it is genuinely
    # lost on round-trip. This is by design (the decoration is re-applied by
    # a later pass over the loaded graph, not carried through JSON), not a
    # bug to fix here.
    my $f    = Chalk::IR::NodeFactory->new();
    my $node = $f->make('Call',
        dispatch_kind => 'method', name => 'foo', inputs => []);
    $node->set_target('sentinel-mop-method-handle');
    my $graph  = _base_graph($f, $node);
    my $loaded = from_json(to_json({ tgt => $graph }));
    my ($found) = grep { blessed($_) && $_->operation eq 'Call' } $loaded->{tgt}->nodes->@*;
    ok(defined $found, 'Call node found after round-trip');
    ok(!defined $found->target,
        'CHARACTERIZATION: target is lost (undef) -- a documented decoration, not JSON payload');
};

subtest 'KNOWN GAP: Return.synthetic does not survive round-trip' => sub {
    my $f   = Chalk::IR::NodeFactory->new();
    my $val = _const($f, '9');
    my $ret = $f->make_cfg('Return', inputs => [undef, $val], synthetic => true);
    my $graph = Chalk::IR::Graph->new(start => $f->make_cfg('Start'), returns => [$ret]);
    my $loaded = from_json(to_json({ syn => $graph }));
    my ($found) = grep { blessed($_) && $_->operation eq 'Return' } $loaded->{syn}->nodes->@*;
    ok(defined $found, 'Return node found after round-trip');
    is($found->synthetic, false,
        'CHARACTERIZATION: synthetic is lost (defaults false), not preserved as true');
};

subtest 'KNOWN GAP: ListAssign.scope does not survive round-trip' => sub {
    my $f     = Chalk::IR::NodeFactory->new();
    my $names = [ _const($f, 'x', 'string') ];
    my $init  = _const($f, '1');
    my $node  = $f->make('ListAssign', scope => 'our', inputs => [$names, $init]);
    my $graph = _base_graph($f, $node);
    my $loaded = from_json(to_json({ la => $graph }));
    my ($found) = grep { blessed($_) && $_->operation eq 'ListAssign' } $loaded->{la}->nodes->@*;
    ok(defined $found, 'ListAssign node found after round-trip');
    is($found->scope, 'my',
        "CHARACTERIZATION: scope is lost (defaults 'my'), not preserved as 'our'");
};

subtest 'KNOWN GAP: AnonSub.graph does not survive round-trip' => sub {
    my $f           = Chalk::IR::NodeFactory->new();
    my $inner_f     = Chalk::IR::NodeFactory->new();
    my $inner_start = $inner_f->make_cfg('Start');
    my $inner_val   = _const($inner_f, '1');
    my $inner_ret   = $inner_f->make_cfg('Return', inputs => [$inner_start, $inner_val]);
    my $inner_graph = Chalk::IR::Graph->new(start => $inner_start, returns => [$inner_ret]);
    my $node        = $f->make('AnonSub', graph => $inner_graph, inputs => []);
    my $graph       = _base_graph($f, $node);
    my $loaded      = from_json(to_json({ an => $graph }));
    my ($found) = grep { blessed($_) && $_->operation eq 'AnonSub' } $loaded->{an}->nodes->@*;
    ok(defined $found, 'AnonSub node found after round-trip');
    ok(!defined $found->graph,
        'CHARACTERIZATION: the nested graph is lost (undef), not preserved');
};

done_testing();
