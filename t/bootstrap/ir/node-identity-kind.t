#!/usr/bin/env perl
# ABOUTME: identity_kind is a property of the node TYPE, not four tables and two constructors.
# ABOUTME: Pins agreement with the tables make() consults, and the entry-point exception.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;

# The question make() answers five different ways: does each occurrence of this
# op get its OWN node, or do textually-identical occurrences share one?
#
#   per_call    -- every make() allocates a fresh node with a counter id.
#                  A distinct side effect, allocation, or control position.
#   hash_consed -- identical content returns the identical node. A pure value.
#
# Today the answer is assembled from four tables (%ROUTED_CFG,
# %STATEMENT_EFFECT_OPS, %ALLOC_OPS, and membership in %DATA_CLASSES) plus
# three ops hardcoded ahead of all of them (Phi, VarDecl, ListAssign), in five
# structurally identical branches.

my %VALID = map { $_ => 1 } qw(per_call hash_consed);

# ---------------------------------------------------------------------------
# The property exists and every node answers it
# ---------------------------------------------------------------------------

subtest 'every node class answers identity_kind with a valid kind' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', const_type => 'integer', value => 1);

    ok $c->can('identity_kind'), 'identity_kind exists on the node type';
    ok $VALID{ $c->identity_kind }, 'Constant answers a valid kind'
        or diag 'got: ' . ($c->identity_kind // 'undef');
};

# ---------------------------------------------------------------------------
# Agreement with OBSERVED make() behaviour
# ---------------------------------------------------------------------------
#
# Not with the tables -- with what make() actually DOES. Calling make() twice
# with identical args and comparing node identity is the ground truth the
# tables exist to produce, and it cannot drift from itself.

subtest 'identity_kind matches what make() actually does' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', const_type => 'integer', value => 1);

    my (@checked, @unbuildable);
    for my $op (_ops()) {
        # Start/Return/Unwind are the documented entry-point exception and are
        # asserted separately below.
        next if $op eq 'Start' || $op eq 'Return' || $op eq 'Unwind';

        my $a = _build($f, $op, $c) or do { push @unbuildable, $op; next };
        my $b = _build($f, $op, $c) or do { push @unbuildable, $op; next };

        my $observed = ($a->id eq $b->id) ? 'hash_consed' : 'per_call';
        is $a->identity_kind, $observed,
            "$op: identity_kind says $observed, and make() agrees";
        push @checked, $op;
    }

    ok scalar(@checked) > 40, 'checked a real share of the vocabulary ('
        . scalar(@checked) . ')';
    diag 'not constructible by the generic helper (NOT checked): '
        . join(' ', @unbuildable) if @unbuildable;
};

# ---------------------------------------------------------------------------
# Both kinds are populated
# ---------------------------------------------------------------------------

subtest 'both kinds are populated -- the partition is not degenerate' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', const_type => 'integer', value => 1);

    my %seen;
    for my $op (_ops()) {
        my $n = _build($f, $op, $c) or next;
        $seen{ $n->identity_kind }++;
    }
    ok $seen{per_call},    'per_call is populated ('    . ($seen{per_call}    // 0) . ')';
    ok $seen{hash_consed}, 'hash_consed is populated (' . ($seen{hash_consed} // 0) . ')';
};

# ---------------------------------------------------------------------------
# THE EXCEPTION, pinned so a refactor cannot quietly erase it
# ---------------------------------------------------------------------------

subtest 'Start/Return/Unwind identity depends on the ENTRY POINT, not the type' => sub {
    # Measured: make() hash-conses these three, make_cfg() allocates fresh.
    # So for them the answer is NOT a pure function of the node type, and
    # identity_kind cannot speak for both constructors.
    #
    # This is the one place the "put it on the type" move does not simply
    # apply, and it is the shape any 4b refactor has to preserve or
    # deliberately change -- never silently drop.
    my $f = Chalk::IR::NodeFactory->new;

    for my $op (qw(Start Return Unwind)) {
        my $a = $f->make($op);
        my $b = $f->make($op);
        is $a->id, $b->id, "$op: make() SHARES one node";

        my $c = $f->make_cfg($op);
        my $d = $f->make_cfg($op);
        isnt $c->id, $d->id, "$op: make_cfg() allocates a FRESH node";
    }
};

subtest 'identity_kind reports the make() answer for the dual-entry ops' => sub {
    # identity_kind describes make(), the entry point the property is for.
    # make_cfg() is a separate constructor with its own contract; a node built
    # through it is per-call regardless of what its type says.
    my $f = Chalk::IR::NodeFactory->new;
    for my $op (qw(Start Return Unwind)) {
        is $f->make($op)->identity_kind, 'hash_consed',
            "$op reports hash_consed (its make() behaviour)";
    }
};

# ---------------------------------------------------------------------------

# The op vocabulary, from the classes on disk.
sub _ops () {
    my %ABSTRACT = map { $_ => 1 } qw(Node BinOp UnaryOp Access Aggregate Regex);
    my @out;
    for my $path (sort glob 'lib/Chalk/IR/Node/*.pm') {
        my ($name) = $path =~ m{([^/]+)\.pm$};
        next if $ABSTRACT{$name};
        push @out, $name;
    }
    return @out;
}

# Required constructor params for classes whose fields are :param without a
# default. Declared above its users -- a `my` below them is empty at run time
# and silently turns every affected class into "could not be constructed".
my %REQUIRED;
BEGIN {
    %REQUIRED = (
        Constant       => { value => 1, const_type => 'integer' },
        PadAccess      => { targ => 1, sigil => '$', symbol => 'x' },
        FieldAccess    => { field_index => 0, field_stash => 'Foo' },
        Coerce         => { from_repr => 'Int', to_repr => 'Str' },
        PostfixDeref   => { sigil => '@' },
        Proj           => { index => 0 },
        EntryDef    => { package => 'main', sigil => '$', symbol => 'x' },
        Call           => { dispatch_kind => 'direct', name => 'f' },
        CompoundAssign => { op => '+=' },
        EnvRead        => { key => 'PATH' },
        RegexCapture   => { n => 1 },
    );
}

# Build a node of $op with identical args each time, or undef.
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

done_testing;
