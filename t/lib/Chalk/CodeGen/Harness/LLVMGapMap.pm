# ABOUTME: LLVM IR-completeness gap-map generator for the computation slice (Phase 3b).
# ABOUTME: Attempts to lower typed SoN graphs to LLVM IR; records L-GREEN/GAP/MISCOMPILE per idiom.
package Chalk::CodeGen::Harness::LLVMGapMap;

use 5.42.0;
use utf8;

use Carp         qw(croak);
use File::Temp   qw(tempfile);
use JSON::PP;
use Chalk::CodeGen::Harness::TypeTag;

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Modulo;
use Chalk::IR::Node::Assign;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::NumGt;
use Chalk::IR::Node::TernaryExpr;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::Coerce;
use Chalk::IR::Node::Return;
use Chalk::IR::Target::LLVM;

# The lli interpreter path (same as in llvm-lowering.t).
my $LLI = '/usr/lib/llvm-15/bin/lli';

# Path for the generated LLVM gap-map artifact.
my $ARTIFACT_FILE = 't/fixtures/codegen-harness/llvm-gap-map.json';

# ---------------------------------------------------------------------------
# Computation-slice idiom registry.
#
# Each entry describes one corpus idiom in the computation slice (groups A,
# C, D, K, L, and literal-arithmetic). For each idiom we record:
#   - tag:         corpus tag (or a synthetic tag for the literal-arithmetic case)
#   - group:       single-letter corpus group
#   - description: human-readable label
#   - build_graph: a coderef that hand-authors the typed SoN graph (or undef if
#                  no graph can be authored yet — treated as GAP with the reason
#                  "no-graph-for-idiom")
#   - perl_oracle: the expected output string from `perl` (used to verify L-GREEN)
#
# The gap-map assesses each idiom against the typed-IR contract. An idiom that
# cannot be lowered runtime-free — because a value has no representation, a
# coercion node is missing, or a guard is absent — is a GAP, and the specific
# reason is recorded.
# ---------------------------------------------------------------------------

# _infer_oracle_tag($oracle_str) -> type-tagged string
# Delegates to Chalk::CodeGen::Harness::TypeTag::infer_tag -- the single
# source of truth for the declared-value tag rule. Converts a plain oracle
# string (e.g. "3", "0.75") to the type-tagged form (e.g. "Int:3", "Num:0.75")
# that lli emits. Already-tagged strings are returned unchanged.
sub _infer_oracle_tag {
    my ($val) = @_;
    return Chalk::CodeGen::Harness::TypeTag::infer_tag($val);
}

# Helper: make a Return node over a value-def chain.
sub _make_return {
    my ($factory, $value_node) = @_;
    return $factory->make_cfg('Return', inputs => [$value_node]);
}

# Helper: make an Int constant.
sub _int_const {
    my ($factory, $val) = @_;
    my $c = $factory->make('Constant', value => "$val", const_type => 'integer');
    $c->set_representation('Int');
    return $c;
}

# Helper: make an Int VarDecl node with an optional initializer.
# Returns ($vd, $name_const) where $vd is the VarDecl and $name_const is
# the Constant node for the variable name.
sub _int_vardecl {
    my ($factory, $varname, $init_node) = @_;
    my $name = $factory->make('Constant', value => $varname, const_type => 'string');
    my $vd   = $factory->make('VarDecl', inputs => [$name, $init_node]);
    $vd->set_representation('Int');
    return ($vd, $name);
}

# Helper: make a PadAccess node reading from a VarDecl slot.
sub _pad_read {
    my ($factory, $vd, $varname) = @_;
    my $pad = $factory->make('PadAccess', targ => 0, varname => $varname, inputs => [$vd]);
    $pad->set_representation('Int');
    return $pad;
}

# ---------------------------------------------------------------------------
# The computation-slice idiom table.
# Each entry: { tag, group, description, build_graph_or_gap, perl_oracle }
#
# build_graph_or_gap is one of:
#   - a coderef returning a Return node (lowerable graph)
#   - undef => GAP: no-graph-for-idiom (the IR cannot even represent the shape)
#
# gap_category (for GAP idioms):
#   representation-missing   — a value in the graph has no representation
#   coercion-missing         — a Coerce node is needed but not insertable
#   guard-missing            — a runtime guard is required (e.g. no-overflow)
#   not-in-computation-slice — idiom is in corpus but not in this slice
#   lowering-not-implemented — representation exists but lowering op not yet coded
#
# ---------------------------------------------------------------------------
sub _idiom_table {
    return (
        # ---------------------------------------------------------------
        # Literal-arithmetic (the only idioms that are L-GREEN today):
        # these use only Int-repr Constants and Int arithmetic ops + Return.
        # No variables, no control flow, no libperl.
        # ---------------------------------------------------------------
        {
            tag         => 'arith-add',
            group       => 'A',  # synthetic — under A for "arithmetic" during reporting
            description => 'literal arithmetic: return 1 + 2',
            perl_oracle => '3',
            build_graph => sub {
                my $f = Chalk::IR::NodeFactory->new;
                my $c1  = _int_const($f, 1);
                my $c2  = _int_const($f, 2);
                my $add = $f->make('Add', inputs => [$c1, $c2]);
                $add->set_representation('Int');
                return _make_return($f, $add);
            },
        },
        {
            tag         => 'arith-sub',
            group       => 'A',
            description => 'literal arithmetic: return 5 - 3',
            perl_oracle => '2',
            build_graph => sub {
                my $f = Chalk::IR::NodeFactory->new;
                my $c5  = _int_const($f, 5);
                my $c3  = _int_const($f, 3);
                my $sub = $f->make('Subtract', inputs => [$c5, $c3]);
                $sub->set_representation('Int');
                return _make_return($f, $sub);
            },
        },
        {
            tag         => 'arith-mul',
            group       => 'A',
            description => 'literal arithmetic: return 3 * 4',
            perl_oracle => '12',
            build_graph => sub {
                my $f = Chalk::IR::NodeFactory->new;
                my $c3  = _int_const($f, 3);
                my $c4  = _int_const($f, 4);
                my $mul = $f->make('Multiply', inputs => [$c3, $c4]);
                $mul->set_representation('Int');
                return _make_return($f, $mul);
            },
        },
        # Division: Perl `/` is always float division (3/4 = 0.75).
        # The correct typed graph: Coerce(Int->Num) both operands, fdiv double,
        # Divide node has Num representation. Phase 3c unlocked this idiom.
        {
            tag         => 'arith-div',
            group       => 'A',
            description => 'literal arithmetic: return 3 / 4 (perl float division = 0.75)',
            perl_oracle => '0.75',
            build_graph => sub {
                my $f    = Chalk::IR::NodeFactory->new;
                my $c3   = _int_const($f, 3);
                my $c4   = _int_const($f, 4);
                my $coe3 = $f->make('Coerce', inputs => [$c3], from_repr => 'Int', to_repr => 'Num');
                $coe3->set_representation('Num');
                my $coe4 = $f->make('Coerce', inputs => [$c4], from_repr => 'Int', to_repr => 'Num');
                $coe4->set_representation('Num');
                my $div  = $f->make('Divide', inputs => [$coe3, $coe4]);
                $div->set_representation('Num');
                return _make_return($f, $div);
            },
        },
        # Modulo: Perl `%` follows the right-operand sign (-7 % 3 = 2, not -1).
        # Phase 3c unlocked this via perl-semantics sign-correction in the backend.
        {
            tag         => 'arith-mod',
            group       => 'A',
            description => 'literal arithmetic: return -7 % 3 (perl right-operand sign = 2)',
            perl_oracle => '2',
            build_graph => sub {
                my $f   = Chalk::IR::NodeFactory->new;
                my $c7  = _int_const($f, -7);
                my $c3  = _int_const($f, 3);
                my $mod = $f->make('Modulo', inputs => [$c7, $c3]);
                $mod->set_representation('Int');
                return _make_return($f, $mod);
            },
        },

        # ---------------------------------------------------------------
        # Group A: variable declarations
        # These require VarDecl nodes, which have no representation field
        # and no LLVM lowering. The IR does not carry representation for
        # allocated stack variables — that is a Phase 3c task.
        # ---------------------------------------------------------------
        {
            tag         => 'A1',
            group       => 'A',
            description => 'VarDecl scalar: my $x = 1; return $x',
            perl_oracle => '1',
            # Phase 3c: VarDecl + PadAccess with Int representation via SSA threading.
            build_graph => sub {
                my $f   = Chalk::IR::NodeFactory->new;
                my $c1  = _int_const($f, 1);
                my ($vd) = _int_vardecl($f, 'x', $c1);
                my $pad = _pad_read($f, $vd, '$x');
                return _make_return($f, $pad);
            },
        },
        {
            tag         => 'A2',
            group       => 'A',
            description => 'VarDecl array literal: my @list = (1,2,3); return scalar @list',
            perl_oracle => '3',
            gap_category => 'representation-missing',
            gap_reason   => 'ArrayRef/ListAssign nodes have no representation; '
                          . 'Perl arrays require Scalar (SV*) representation — '
                          . 'no runtime-free lowering exists for array allocation.',
            build_graph  => undef,
        },
        {
            tag         => 'A3',
            group       => 'A',
            description => 'VarDecl hash literal: my %h = (a=>1,b=>2); return $h{a}',
            perl_oracle => '1',
            gap_category => 'representation-missing',
            gap_reason   => 'HashRef/Subscript nodes have no representation; '
                          . 'Perl hashes require Scalar (SV*) — no runtime-free lowering.',
            build_graph  => undef,
        },
        {
            tag         => 'A4',
            group       => 'A',
            description => 'VarDecl no initializer: my $x; $x = 1; return $x',
            perl_oracle => '1',
            # Phase 3c: VarDecl(undef init) + Assign in control chain.
            build_graph => sub {
                my $f    = Chalk::IR::NodeFactory->new;
                my ($vd) = _int_vardecl($f, 'x', undef);  # no initializer
                my $c1   = _int_const($f, 1);

                # Assign: lhs=PadAccess, rhs=Constant(1), control_in=VarDecl
                my $lhs  = _pad_read($f, $vd, '$x_lhs');
                my $asgn = $f->make('Assign', inputs => [$lhs, $c1]);
                $asgn->set_representation('Int');
                $asgn->set_control_in($vd);

                my $pad = _pad_read($f, $vd, '$x');
                my $ret = _make_return($f, $pad);
                $ret->set_control_in($asgn);
                return $ret;
            },
        },
        {
            tag         => 'A5',
            group       => 'A',
            description => 'VarDecl field: field $x :param; return $x',
            perl_oracle => '42',
            gap_category => 'representation-missing',
            gap_reason   => 'FieldAccess node has no representation; object fields '
                          . 'require layout knowledge (struct offset) not yet in IR.',
            build_graph  => undef,
        },

        # ---------------------------------------------------------------
        # Group C: assignments
        # ---------------------------------------------------------------
        {
            tag         => 'C1',
            group       => 'C',
            description => 'reassignment: my $x = 1; $x = 2; return $x',
            perl_oracle => '2',
            # Phase 3c: reassignment via Assign in control chain.
            build_graph => sub {
                my $f    = Chalk::IR::NodeFactory->new;
                my $c1   = _int_const($f, 1);
                my $c2   = _int_const($f, 2);
                my ($vd) = _int_vardecl($f, 'x', $c1);
                my $lhs  = _pad_read($f, $vd, '$x_lhs');
                my $asgn = $f->make('Assign', inputs => [$lhs, $c2]);
                $asgn->set_representation('Int');
                $asgn->set_control_in($vd);
                my $pad = _pad_read($f, $vd, '$x');
                my $ret = _make_return($f, $pad);
                $ret->set_control_in($asgn);
                return $ret;
            },
        },
        {
            tag         => 'C2',
            group       => 'C',
            description => 'compound assignment: my $x = 1; $x += 2; return $x',
            perl_oracle => '3',
            # Phase 3c: CompoundAssign (+=) via SSA threading.
            build_graph => sub {
                my $f    = Chalk::IR::NodeFactory->new;
                my $c1   = _int_const($f, 1);
                my $c2   = _int_const($f, 2);
                my ($vd) = _int_vardecl($f, 'x', $c1);
                # The read side of +=: current $x value
                my $read = _pad_read($f, $vd, '$x_r');
                my $sum  = $f->make('Add', inputs => [$read, $c2]);
                $sum->set_representation('Int');
                # CompoundAssign: lhs=PadAccess, rhs=computed sum
                my $lhs  = _pad_read($f, $vd, '$x_l');
                my $ca   = $f->make('CompoundAssign', op => '+=', inputs => [$lhs, $sum]);
                $ca->set_representation('Int');
                $ca->set_control_in($vd);
                my $pad = _pad_read($f, $vd, '$x');
                my $ret = _make_return($f, $pad);
                $ret->set_control_in($ca);
                return $ret;
            },
        },
        {
            tag         => 'C3',
            group       => 'C',
            description => 'string concat assign: my $s = "a"; $s .= "b"; return $s',
            perl_oracle => 'ab',
            gap_category => 'representation-missing',
            gap_reason   => 'Concat/.= operates on Str representation which is not '
                          . 'yet lowerable runtime-free (Str = char*/SV* — no '
                          . 'runtime-free string layout in the IR).',
            build_graph  => undef,
        },
        {
            tag         => 'C4',
            group       => 'C',
            description => 'array element assignment: my @a = (1); $a[0] = 2; return $a[0]',
            perl_oracle => '2',
            gap_category => 'representation-missing',
            gap_reason   => 'Array Subscript + Assign has no representation; '
                          . 'array element access requires Scalar (SV*).',
            build_graph  => undef,
        },
        {
            tag         => 'C5',
            group       => 'C',
            description => 'hash element assignment: my %h = (); $h{k} = 1; return $h{k}',
            perl_oracle => '1',
            gap_category => 'representation-missing',
            gap_reason   => 'Hash Subscript + Assign has no representation; '
                          . 'hash element access requires Scalar (SV*).',
            build_graph  => undef,
        },

        # ---------------------------------------------------------------
        # Group D: control flow
        # ---------------------------------------------------------------
        {
            tag         => 'D1',
            group       => 'D',
            description => 'if/else: my $x = 0; if ($n > 0) { $x=1 } else { $x=2 }; return $x',
            perl_oracle => '1',
            gap_category => 'representation-missing',
            gap_reason   => 'If/Phi control flow requires: (1) condition operand with '
                          . 'representation (Bool or Int), (2) Phi node carrying '
                          . 'representation for the join value. Neither Phi nor the '
                          . 'If condition carries representation in the current IR. '
                          . 'Additionally, the method parameter $n has no representation.',
            build_graph  => undef,
        },
        {
            tag         => 'D2',
            group       => 'D',
            description => 'while loop: my $i = 0; while ($i < 3) { $i = $i + 1; } return $i',
            perl_oracle => '3',
            gap_category => 'representation-missing',
            gap_reason   => 'Loop/Phi backedge requires Phi nodes with representation '
                          . 'and back-edge-safe coercion ordering (per typed-ir-repr §1a '
                          . 'M2 note). Neither Loop nor Phi carries representation in '
                          . 'the current IR.',
            build_graph  => undef,
        },
        {
            tag         => 'D3',
            group       => 'D',
            description => 'foreach loop: my $sum = 0; foreach my $n (1,2,3) { $sum=$sum+$n; }; return $sum',
            perl_oracle => '6',
            gap_category => 'representation-missing',
            gap_reason   => 'ForEach loop requires: iterator Phi with representation, '
                          . 'loop variable $n with representation (PadAccess not on graph). '
                          . 'Same gap class as D2.',
            build_graph  => undef,
        },
        {
            tag         => 'D4',
            group       => 'D',
            description => 'postfix if: my $x = 0; $x = 1 if $n > 0; return $x',
            perl_oracle => '1',
            gap_category => 'representation-missing',
            gap_reason   => 'Postfix-if control flow requires If node with Bool-repr '
                          . 'condition and Phi for the join; same gap class as D1.',
            build_graph  => undef,
        },
        {
            tag         => 'D5',
            group       => 'D',
            description => 'postfix while: my $i = 0; $i = $i+1 while $i < 3; return $i',
            perl_oracle => '3',
            gap_category => 'representation-missing',
            gap_reason   => 'Postfix-while is a Loop/Phi pattern; same gap class as D2.',
            build_graph  => undef,
        },
        {
            tag         => 'D6',
            group       => 'D',
            description => 'ternary: my $x = $n > 0 ? 1 : 2; return $x',
            perl_oracle => '1',
            # Phase 3c: TernaryExpr lowers to LLVM select when condition has Bool repr
            # and branches have Int repr. $n = 5 (Int constant standing in for the
            # parameter, which would be Scalar in production — gap at the caller boundary).
            build_graph => sub {
                my $f    = Chalk::IR::NodeFactory->new;
                my $n    = _int_const($f, 5);      # $n = 5 (Int-proven constant)
                my $zero = _int_const($f, 0);
                my $cmp  = $f->make('NumGt', inputs => [$n, $zero]);
                $cmp->set_representation('Bool');
                my $c1   = _int_const($f, 1);
                my $c2   = _int_const($f, 2);
                my $tern = $f->make('TernaryExpr', inputs => [$cmp, $c1, $c2]);
                $tern->set_representation('Int');
                # my $x = ternary result
                my ($vd) = _int_vardecl($f, 'x', $tern);
                my $pad  = _pad_read($f, $vd, '$x');
                return _make_return($f, $pad);
            },
        },
        {
            tag         => 'D7',
            group       => 'D',
            description => 'nested if: if ($n>0) { if ($n>5) {$x=1} else {$x=2} } else {$x=3}; return $x',
            perl_oracle => '1',
            gap_category => 'representation-missing',
            gap_reason   => 'Nested If/Phi: same gap class as D1, compounded by '
                          . 'two levels of Phi merge.',
            build_graph  => undef,
        },
        {
            tag         => 'D8',
            group       => 'D',
            description => 'try/catch: try { die "boom"; } catch ($e) { return 0; } return 1',
            perl_oracle => '0',
            gap_category => 'representation-missing',
            gap_reason   => 'TryCatch node has no representation; exception handling '
                          . 'requires a landing-pad mechanism (LLVM personality + invoke) '
                          . 'not yet modelled in the IR.',
            build_graph  => undef,
        },

        # ---------------------------------------------------------------
        # Group K: increment
        # ---------------------------------------------------------------
        {
            tag         => 'K1',
            group       => 'K',
            description => 'pre-increment: my $i = 0; ++$i; return $i',
            perl_oracle => '1',
            # Phase 3c: pre-increment is a CompoundAssign(+=1) in the control chain.
            build_graph => sub {
                my $f    = Chalk::IR::NodeFactory->new;
                my $c0   = _int_const($f, 0);
                my $c1   = _int_const($f, 1);
                my ($vd) = _int_vardecl($f, 'i', $c0);
                # ++$i: read current, add 1, assign back
                my $read = _pad_read($f, $vd, '$i_r');
                my $sum  = $f->make('Add', inputs => [$read, $c1]);
                $sum->set_representation('Int');
                my $lhs  = _pad_read($f, $vd, '$i_l');
                my $ca   = $f->make('CompoundAssign', op => '+=', inputs => [$lhs, $sum]);
                $ca->set_representation('Int');
                $ca->set_control_in($vd);
                my $pad  = _pad_read($f, $vd, '$i');
                my $ret  = _make_return($f, $pad);
                $ret->set_control_in($ca);
                return $ret;
            },
        },
        {
            tag         => 'K2',
            group       => 'K',
            description => 'post-increment: my $i = 0; $i++; return $i',
            perl_oracle => '1',
            # Phase 3c: post-increment side-effect is a CompoundAssign(+=1);
            # the return is $i AFTER the increment (both return 1 from 0).
            # The distinction from K1 (what expression $i++ vs ++$i produces)
            # is immaterial here since return is always of $i, not the expr.
            build_graph => sub {
                my $f    = Chalk::IR::NodeFactory->new;
                my $c0   = _int_const($f, 0);
                my $c1   = _int_const($f, 1);
                my ($vd) = _int_vardecl($f, 'i', $c0);
                # $i++: same side-effect graph as K1 for the purpose of `return $i`
                my $read = _pad_read($f, $vd, '$i_r');
                my $sum  = $f->make('Add', inputs => [$read, $c1]);
                $sum->set_representation('Int');
                my $lhs  = _pad_read($f, $vd, '$i_l');
                my $ca   = $f->make('CompoundAssign', op => '+=', inputs => [$lhs, $sum]);
                $ca->set_representation('Int');
                $ca->set_control_in($vd);
                my $pad  = _pad_read($f, $vd, '$i');
                my $ret  = _make_return($f, $pad);
                $ret->set_control_in($ca);
                return $ret;
            },
        },

        # ---------------------------------------------------------------
        # Group L: logical operators
        # ---------------------------------------------------------------
        {
            tag         => 'L1',
            group       => 'L',
            description => 'logical and: return $a && $b',
            perl_oracle => '2',  # (1 && 2) = 2 under perl
            gap_category => 'representation-missing',
            gap_reason   => 'The And node operates on Scalar-typed arguments ($a, $b '
                          . 'are method parameters with no on-graph representation). '
                          . 'Logical && in Perl returns a value (not just a bool), '
                          . 'so it requires Scalar representation or a proven-bool '
                          . 'narrowing coercion. Neither is in the current IR.',
            build_graph  => undef,
        },
        {
            tag         => 'L2',
            group       => 'L',
            description => 'logical or: return $a || $b',
            perl_oracle => '3',  # (0 || 3) = 3
            gap_category => 'representation-missing',
            gap_reason   => 'Same gap as L1: Or node on Scalar-repr parameters.',
            build_graph  => undef,
        },
        {
            tag         => 'L3',
            group       => 'L',
            description => 'defined-or: return $a // $b',
            perl_oracle => '4',  # (undef // 4) = 4
            gap_category => 'representation-missing',
            gap_reason   => 'DefinedOr requires a defined-check on an SV* — inherently '
                          . 'Scalar. No runtime-free defined-check exists in the current IR.',
            build_graph  => undef,
        },
        {
            tag         => 'L4',
            group       => 'L',
            description => 'not: return !$a',
            perl_oracle => '1',  # (!0) = 1
            gap_category => 'representation-missing',
            gap_reason   => 'Not (!) on a Scalar parameter: the negation result type '
                          . '(Bool/Int) and the operand representation are both absent '
                          . 'from the IR. Without a proven-bool input, ! requires '
                          . 'Scalar coercion.',
            build_graph  => undef,
        },
    );
}

# ---------------------------------------------------------------------------
# generate() -> \%llvm_gap_map
#
# Iterates all computation-slice idioms, attempts to lower each to LLVM IR,
# and records L-GREEN / GAP / MISCOMPILE per idiom.
#
# L-GREEN requirements (all must hold):
#   1. lower() succeeds without dying.
#   2. Generated .ll contains NO perl C-API calls (Perl_/SV/libperl).
#   3. Every value-def in the graph has a non-Scalar representation (100% coverage).
#   4. lli exits 0 and its stdout matches the perl oracle.
#
# GAP: lower() died, OR the generated .ll contains libperl, OR coverage < 100%.
# MISCOMPILE: lower() succeeded, libperl-free, 100% coverage, but lli != oracle.
#
# Also writes the artifact to t/fixtures/codegen-harness/llvm-gap-map.json.
# ---------------------------------------------------------------------------
sub generate {
    my (undef) = @_;    # class method

    my @idioms   = _idiom_table();
    my @entries;

    for my $idiom (@idioms) {
        my $entry = _assess_one($idiom);
        push @entries, $entry;
    }

    my $summary  = _build_summary(\@entries);
    my $gap_map  = { entries => \@entries, summary => $summary };

    _write_artifact($gap_map);

    return $gap_map;
}

# ---------------------------------------------------------------------------
# verdict_for_scalar_graph() -> verdict_string
#
# False-green guard test: hand-authors a graph with a Scalar-representation
# Constant and attempts to lower it. Must verdict GAP, never L-GREEN.
# ---------------------------------------------------------------------------
sub verdict_for_scalar_graph {
    my (undef) = @_;    # class method

    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', value => '42', const_type => 'integer');
    $c->set_representation('Scalar');    # deliberately Scalar — the false-green guard

    my $ret = $f->make_cfg('Return', inputs => [$c]);

    my $idiom = {
        tag         => '_scalar_guard',
        group       => '_guard',
        description => 'false-green guard: Scalar-repr constant must verdict GAP',
        perl_oracle => '42',
        build_graph => sub { $ret },
    };

    my $entry = _assess_one($idiom);
    return $entry->{verdict};
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# Assess one idiom and return an entry hashref.
sub _assess_one {
    my ($idiom) = @_;

    my $tag   = $idiom->{tag};
    my $group = $idiom->{group};
    my $desc  = $idiom->{description};

    # No build_graph: pre-classified GAP (IR cannot represent this idiom yet).
    unless (defined $idiom->{build_graph}) {
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'GAP',
            extra   => {
                description  => $desc,
                gap_reason   => $idiom->{gap_reason}
                              // 'no typed SoN graph can be authored for this idiom '
                              . '(IR underspecified for this shape)',
                gap_category => $idiom->{gap_category} // 'representation-missing',
                libperl_free           => undef,
                runtime_free_coverage  => undef,
            },
        };
    }

    # Build the graph.
    my $return_node = eval { $idiom->{build_graph}->() };
    if ($@) {
        my $err = $@;
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'GAP',
            extra   => {
                description  => $desc,
                gap_reason   => "graph construction failed: $err",
                gap_category => 'lowering-not-implemented',
                libperl_free           => undef,
                runtime_free_coverage  => undef,
            },
        };
    }

    # Compute runtime-free coverage: what fraction of value-defs have non-Scalar repr?
    my ($coverage, $scalar_count, $total_defs) = _compute_coverage($return_node);

    # Attempt to lower to LLVM IR text.
    my $ll = eval { Chalk::IR::Target::LLVM->lower($return_node) };
    if ($@) {
        my $err = $@;
        # lower() died — this is a GAP (Scalar reached backend, or unsupported op).
        my $gap_cat = ($err =~ /GAP/)          ? 'representation-missing'
                    : ($err =~ /cannot lower/)  ? 'lowering-not-implemented'
                    :                             'lowering-not-implemented';
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'GAP',
            extra   => {
                description           => $desc,
                gap_reason            => "lower() died: $err",
                gap_category          => $gap_cat,
                libperl_free          => undef,
                runtime_free_coverage => $coverage,
            },
        };
    }

    # Check the false-green guard: no perl C-API calls in the generated .ll.
    my $libperl_free = ($ll !~ /Perl_/ && $ll !~ /\bSV\b/ && $ll !~ /libperl/) ? 1 : 0;
    unless ($libperl_free) {
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'GAP',
            extra   => {
                description           => $desc,
                gap_reason            => 'generated .ll contains perl C-API calls '
                                       . '(Perl_/SV/libperl) — not runtime-free',
                gap_category          => 'representation-missing',
                libperl_free          => 0,
                runtime_free_coverage => $coverage,
            },
        };
    }

    # Coverage guard: 100% runtime-free required for L-GREEN.
    if ($coverage < 1.0) {
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'GAP',
            extra   => {
                description           => $desc,
                gap_reason            => sprintf(
                    'runtime-free coverage %.0f%% < 100%%: %d of %d value-defs are Scalar',
                    $coverage * 100, $scalar_count, $total_defs
                ),
                gap_category          => 'representation-missing',
                libperl_free          => 1,
                runtime_free_coverage => $coverage,
            },
        };
    }

    # Run through lli to compare against the perl oracle.
    my ($lli_out, $lli_exit) = _run_lli($ll);

    my $oracle_raw = $idiom->{perl_oracle} // '';
    # The lli output is type-tagged (e.g. "Int:3", "Num:0.75"). The oracle
    # strings in _idiom_table may be plain ("3") or already tagged ("Int:3").
    # Infer a tag for the oracle so both sides are comparable.
    my $oracle = _infer_oracle_tag($oracle_raw);

    # MISCOMPILE: lowered correctly but behavior diverges.
    if ($lli_exit != 0 || $lli_out ne $oracle) {
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'MISCOMPILE',
            extra   => {
                description           => $desc,
                lli_output            => $lli_out,
                perl_oracle           => $oracle,
                lli_exit              => $lli_exit,
                libperl_free          => 1,
                runtime_free_coverage => $coverage,
            },
        };
    }

    # L-GREEN: fully runtime-free, libperl-free, 100% coverage, lli == oracle.
    return {
        tag     => $tag,
        group   => $group,
        verdict => 'L-GREEN',
        extra   => {
            description           => $desc,
            lli_output            => $lli_out,
            perl_oracle           => $oracle,
            libperl_free          => 1,
            runtime_free_coverage => $coverage,
        },
    };
}

# Collect all value-def nodes reachable from the Return node's data inputs.
# Returns (coverage_fraction, scalar_count, total_defs).
sub _collect_data_nodes {
    my ($return_node) = @_;
    my %seen;
    my @queue;
    my @data_nodes;

    my $inputs = $return_node->inputs // [];
    for my $inp ($inputs->@*) {
        next unless defined $inp;
        push @queue, $inp;
    }

    while (@queue) {
        my $node = shift @queue;
        next unless defined $node;
        my $id = $node->id;
        next if $seen{$id}++;
        push @data_nodes, $node;
        my $node_inputs = $node->inputs // [];
        for my $inp ($node_inputs->@*) {
            next unless defined $inp;
            push @queue, $inp;
        }
    }
    return @data_nodes;
}

sub _compute_coverage {
    my ($return_node) = @_;
    my @data_nodes = _collect_data_nodes($return_node);
    my $total  = scalar @data_nodes;
    return (1.0, 0, 0) unless $total;

    my $scalar_count = grep {
        defined $_->representation && $_->representation eq 'Scalar'
    } @data_nodes;

    my $coverage = ($total - $scalar_count) / $total;
    return ($coverage, $scalar_count, $total);
}

# Run the .ll text through lli; return (stdout_chomped, exit_code).
sub _run_lli {
    my ($ll_text) = @_;

    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll_text;
    close $fh;

    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($out, $exit);
}

# Build summary section from entries.
sub _build_summary {
    my ($entries) = @_;
    my (%by_verdict, %by_group);
    for my $e (@$entries) {
        my $v = $e->{verdict} // 'UNKNOWN';
        my $g = $e->{group}   // 'UNKNOWN';
        $by_verdict{$v}++;
        $by_group{$g}{count}++;
        $by_group{$g}{verdicts}{$v}++;
    }
    return {
        denominator => scalar(@$entries),
        by_verdict  => \%by_verdict,
        by_group    => \%by_group,
    };
}

# Write the artifact JSON.
sub _write_artifact {
    my ($gap_map) = @_;

    my $dir = $ARTIFACT_FILE;
    $dir =~ s|/[^/]+$||;
    unless (-d $dir) {
        mkdir $dir or croak "LLVMGapMap: cannot create artifact dir '$dir': $!";
    }

    open my $fh, '>', $ARTIFACT_FILE
        or croak "LLVMGapMap: cannot write artifact '$ARTIFACT_FILE': $!";

    my $json = JSON::PP->new->utf8->canonical->pretty->encode($gap_map);
    print $fh $json;
    close $fh;
}

1;
