#!/usr/bin/env perl
# ABOUTME: staleness_kind is a property of the node TYPE, not two op-name lists.
# ABOUTME: Pins the partition is TOTAL, so a new op cannot silently answer "opaque".

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM::Context;

# The question: may a cached SSA ref for this node go STALE across a store?
#
#   mutable_read -- reads a mutable location. Answer YES, stop.
#   transparent  -- my value is stale exactly when an input's is. Descend.
#   opaque       -- fixed SSA value at a single program point. Answer NO, stop.
#
# NOTE "transparent", not "pure". Coerce, Interpolate and TernaryExpr are in
# this bucket and none is pure in any ordinary sense. The property is whether
# staleness PASSES THROUGH the node, which is a different question from purity.

my @KINDS = qw(mutable_read transparent opaque);
my %VALID = map { $_ => 1 } @KINDS;

# Required constructor params, for the classes whose fields are :param without
# a default. Supplied explicitly so a construction failure is a REAL failure
# rather than a gap in this helper — the trap step 1 hit, where a subtest
# pass()ed on a class it had never actually built.
#
# Declared HERE, above the subtests, because the helper closes over it: a `my`
# declared below its use point is empty when the subtests run, which silently
# turned every one of these into "could not be constructed".
my %REQUIRED = (
    Constant     => { value => 1, const_type => 'integer' },
    PadAccess    => { targ => 1, varname => '$x' },
    FieldAccess  => { field_index => 0, field_stash => 'Foo' },
    Coerce       => { from_repr => 'Int', to_repr => 'Str' },
    PostfixDeref => { sigil => '@' },
    Proj         => { index => 0 },
    StashAccess    => { stash_name => 'main', var_name => 'x' },
    Call           => { dispatch_kind => 'direct', name => 'f' },
    CompoundAssign => { op => '+=' },
    EnvRead        => { key => 'PATH' },
    RegexCapture   => { n => 1 },
);

# ---------------------------------------------------------------------------
# Every node answers, and answers something valid
# ---------------------------------------------------------------------------

subtest 'every node class answers staleness_kind with a valid kind' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', const_type => 'integer', value => 1);

    ok $c->can('staleness_kind'), 'staleness_kind exists on the node type';
    ok $VALID{ $c->staleness_kind }, 'Constant answers a valid kind'
        or diag 'got: ' . ($c->staleness_kind // 'undef');
};

# ---------------------------------------------------------------------------
# Agreement with the registries it replaces
# ---------------------------------------------------------------------------
#
# This is the step-1 pattern: the method and the registry must AGREE on every
# op the registry names, so a later deletion of the registry cannot change
# behaviour silently and a divergence fails loudly.

subtest 'staleness_kind agrees with %MUTABLE_READ_OPS' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', const_type => 'integer', value => 1);

    my @ops = Chalk::Target::LLVM::Context::_mutable_read_ops();
    ok scalar(@ops), 'the registry is non-empty (' . scalar(@ops) . ')';

    for my $op (@ops) {
        my $n = _build($f, $op, $c) or do {
            fail "$op could not be constructed -- agreement NOT checked";
            next;
        };
        is $n->staleness_kind, 'mutable_read',
            "$op is mutable_read (registry says so)";
    }
};

subtest 'staleness_kind agrees with %PURE_DESCEND_OPS' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', const_type => 'integer', value => 1);

    my @ops = Chalk::Target::LLVM::Context::_pure_descend_ops();
    ok scalar(@ops), 'the registry is non-empty (' . scalar(@ops) . ')';

    for my $op (@ops) {
        my $n = _build($f, $op, $c) or do {
            fail "$op could not be constructed -- agreement NOT checked";
            next;
        };
        is $n->staleness_kind, 'transparent',
            "$op is transparent (registry says descend)";
    }
};

# ---------------------------------------------------------------------------
# THE POINT OF THIS FILE: the partition is TOTAL
# ---------------------------------------------------------------------------

subtest 'the third bucket is DECLARED, not defined by absence' => sub {
    # The registry pair answers "opaque" by falling off the end of an
    # if/elsif. That makes a new op silently answer "no, it cannot go stale"
    # -- and a wrong "no" serves a stale SSA ref across a store, which is the
    # whole-branch review C1/C2 miscompile class.
    #
    # With the property on the type, an op that never declares its kind
    # inherits the base-class default. That default must therefore be the
    # CONSERVATIVE answer, not the convenient one.
    my $f = Chalk::IR::NodeFactory->new;

    # Statement effects execute once at a control position: their result ref
    # is fixed, so opaque is correct for them and they say so explicitly.
    my $c = $f->make('Constant', const_type => 'integer', value => 1);
    for my $op (qw(Print Assign)) {
        my $n = _build($f, $op, $c) or next;
        is $n->staleness_kind, 'opaque', "$op is opaque (fixed at a control position)";
    }

    # Values fixed at a single program point.
    is $c->staleness_kind, 'opaque', 'Constant is opaque';
};

subtest 'the base-class default is the CONSERVATIVE answer' => sub {
    # The default is the safety property. If a new node class forgets to
    # declare its kind, the answer must be the one that costs performance
    # rather than the one that miscompiles.
    #
    # Under the registry pair the default was "opaque" -- fall off the end of
    # the if/elsif and answer "no, this cannot go stale". That is the WRONG
    # direction: a wrong "no" serves a stale SSA ref across a store. A wrong
    # "mutable_read" only re-lowers a node that did not need re-lowering.
    # Every shipped class declares its kind explicitly, so the default is
    # exercised by a class that does NOT -- which is exactly the situation
    # this default exists for: a node class added later whose author did not
    # think about staleness.
    {
        no warnings 'once';
        @Chalk::IR::Node::_TestUndeclared::ISA = ('Chalk::IR::Node');
    }
    my $n = bless {}, 'Chalk::IR::Node::_TestUndeclared';

    is Chalk::IR::Node::_TestUndeclared->can('staleness_kind'),
       Chalk::IR::Node->can('staleness_kind'),
       'an undeclared subclass inherits the base implementation';

    # And the inherited answer is the conservative one. Read off a real node
    # of the base class rather than the blessed stub, since a `feature class`
    # method needs a real instance.
    my $f = Chalk::IR::NodeFactory->new;
    my $probe = $f->make('Constant', const_type => 'integer', value => 1);
    my $base_default = Chalk::IR::Node->can('staleness_kind')->($probe);
    is $base_default, 'mutable_read',
        'the inherited default is mutable_read (wrong answer costs speed, not correctness)';
};

# ---------------------------------------------------------------------------
# Totality against the node vocabulary
# ---------------------------------------------------------------------------

subtest 'every constructible node class is classified' => sub {
    # Walk the real class list rather than a hand-kept op list, so a node
    # class added tomorrow is covered by this test the day it lands.
    my @classes = _node_classes();
    ok scalar(@classes) > 50, 'found the node classes (' . scalar(@classes) . ')';

    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', const_type => 'integer', value => 1);

    my (@unclassified, @unbuildable, %seen_kind);
    for my $class (@classes) {
        my $op = $class =~ s/.*:://r;
        my $n  = _build($f, $op, $c);
        if (!$n) { push @unbuildable, $op; next }

        my $kind = eval { $n->staleness_kind };
        if (!defined $kind || !$VALID{$kind}) {
            push @unclassified, $op;
            next;
        }
        $seen_kind{$kind}++;
    }

    is_deeply \@unclassified, [],
        'every constructible node class answers a valid staleness_kind'
        or diag "unclassified: @unclassified";

    # All three buckets must be populated, or the partition is degenerate and
    # this test would pass against a stub returning one constant.
    ok $seen_kind{mutable_read}, 'mutable_read is populated ('
        . ($seen_kind{mutable_read} // 0) . ')';
    ok $seen_kind{transparent},  'transparent is populated ('
        . ($seen_kind{transparent}  // 0) . ')';
    ok $seen_kind{opaque},       'opaque is populated ('
        . ($seen_kind{opaque}       // 0) . ')';

    # Report rather than fail: a class needing constructor params this helper
    # does not supply is a gap in the HELPER, not in the classification. It is
    # diagnosed loudly so it cannot masquerade as coverage.
    diag 'not constructible by the generic helper (NOT checked): '
        . join(' ', @unbuildable) if @unbuildable;
};

# ---------------------------------------------------------------------------

# Build a node of $op with a plausible operand, or undef if it cannot be built.
sub _build ($f, $op, $operand) {
    my %req = ($REQUIRED{$op} // {})->%*;
    for my $shape (
        sub { $f->make($op, %req, inputs => [undef, $operand, $operand],
                            left => $operand, right => $operand) },
        sub { $f->make($op, %req, inputs => [$operand, $operand]) },
        sub { $f->make($op, %req, inputs => [$operand]) },
        sub { $f->make($op, %req, inputs => []) },
    ) {
        my $n = eval { $shape->() };
        return $n if $n;
    }
    return undef;
}

# The node classes, read from disk so a new one is covered automatically.
# Abstract bases are excluded: they are never instantiated.
sub _node_classes () {
    my %ABSTRACT = map { $_ => 1 }
        qw(Node BinOp UnaryOp Access Aggregate Regex);
    my @out;
    for my $path (sort glob 'lib/Chalk/IR/Node/*.pm') {
        my ($name) = $path =~ m{([^/]+)\.pm$};
        next if $ABSTRACT{$name};
        push @out, "Chalk::IR::Node::$name";
    }
    return @out;
}

done_testing;
