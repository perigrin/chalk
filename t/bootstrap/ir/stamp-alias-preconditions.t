# ABOUTME: Pins the preconditions that make the representation->stamp alias sound.
# ABOUTME: One field, two names -- so a type reader would currently read Slot and be wrong.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::IR::Node::Constant;

# `representation`/`set_representation` are a deprecated ALIAS for
# `stamp`/`set_stamp` (Chalk::IR::Node, slice 3a of
# docs/plans/2026-08-24-loader-analysis-pipeline.md). The alias is
# behaviour-preserving TODAY because of two facts that nothing else asserts.
# This file asserts them, so that when either stops being true it fails here
# with an explanation rather than silently downstream.

subtest 'the alias is ONE FIELD, both directions' => sub {
    my $n = Chalk::IR::Node::Constant->new(id => 'a', value => 1);

    $n->set_representation('Int');
    is $n->stamp,          'Int', 'set_representation is visible as stamp';
    is $n->representation, 'Int', 'and as representation';

    $n->set_stamp('Str');
    is $n->representation, 'Str', 'set_stamp is visible as representation';
    is $n->stamp,          'Str', 'and as stamp';
};

subtest 'set_representation DESTROYS the type -- this is not symmetric' => sub {
    # The alias is not "two names for the same fact" in both directions. A
    # representation write overwrites whatever type was there. That is fine
    # only while the type axis has no consumer; see the next subtest.
    my $n = Chalk::IR::Node::Constant->new(id => 'b', value => 2);
    $n->set_stamp('Int');
    $n->set_representation('Slot');
    is $n->stamp, 'Slot',
        'a Slot representation write leaves Slot in the TYPE field';
    isnt $n->stamp, 'Int',
        'the Int type is gone -- destructive, by construction';
};

subtest 'PRECONDITION: no UNGUARDED reader of the type axis in lib/' => sub {
    # RESOLVED 2026-08-29 (`3396682a`) -- and resolved the way this comment
    # said to resolve it. It used to read:
    #
    #   "The loader writes `Slot` ... `Slot` is not a member of the type
    #    lattice. Every provably-OOB element read therefore has a corrupted
    #    type axis after loading. ... Fixing this test means fixing the OOB
    #    path to write a TYPE, not deleting the assertion."
    #
    # The OOB path now writes `Undef` -- a lattice member, and the exact type
    # the old comment named as honest. The producer independently agrees: an
    # out-of-range literal index and an absent literal hash key both arrive
    # stamped `Undef`. So no lib/ writer puts a non-type into the shared field
    # any more, and a ->stamp reader can no longer be poisoned by one.
    #
    # THE ASSERTION STAYS, per its own instruction, but its job has changed:
    # it now guards against the hazard RETURNING rather than documenting a live
    # one. A new unguarded reader is no longer a bug by itself -- what would be
    # a bug is a new WRITER of a non-lattice name, which is what this catches
    # by keeping readers honest about the field they are reading.
    #
    # NARROWED 2026-08-26, when the first legitimate reader arrived. `to_json`
    # must read the stamp -- a serializer that cannot emit the type axis means
    # chalk cannot hand a typed graph to anything, including a future chalk.
    # It reads the field and then REFUSES to emit a non-lattice value, via
    # TypeLibrary::is_lattice_type, so `Slot` is dropped rather than written to
    # the wire.
    #
    # That is the shape a safe reader has: read, then check membership before
    # believing it. The sweep therefore exempts a reader on a line that also
    # tests lattice membership, and still fails on a bare one. It is a
    # heuristic -- a reader that checks membership three lines later passes
    # this and should not -- but it discriminates the case that exists, and a
    # heuristic that names its limit beats an assertion quietly deleted.
    my $root = 'lib';
    my @readers;
    my @files;
    my $walk;
    $walk = sub ($dir) {
        opendir(my $dh, $dir) or return;
        for my $e (sort readdir $dh) {
            next if $e =~ /^\./;
            my $p = "$dir/$e";
            if (-d $p) { $walk->($p) }
            elsif ($p =~ /\.pm$/) { push @files, $p }
        }
        closedir $dh;
    };
    $walk->($root);

    # A guard is not always on the reader's own line -- `to_json`'s spans an
    # if-condition and its body. Read each file whole and look for the check
    # within a few lines ABOVE the read, which is where a guard lives.
    my $GUARD_WINDOW = 4;

    for my $f (@files) {
        # Chalk::IR::Node itself defines the accessors; it is not a consumer.
        next if $f eq 'lib/Chalk/IR/Node.pm';
        # Chalk::IR::Analysis reads ->stamp in _assert_value_nodes_are_typed,
        # which asks only whether a stamp is PRESENT and never interprets its
        # value. That is the one read the `Slot` corruption cannot mislead, so
        # it is not the consumer this precondition is guarding against.
        next if $f eq 'lib/Chalk/IR/Analysis.pm';
        open my $fh, '<', $f or next;
        my @lines = <$fh>;
        close $fh;

        for my $i (0 .. $#lines) {
            my $line = $lines[$i];
            next if $line =~ /^\s*#/;              # comments are not readers
            next unless $line =~ /->stamp\b/;
            next if $line =~ /->stamp\s*\(/;       # a call, not the reader

            # A reader that checks lattice membership -- on its own line or in
            # the guard just above -- has done the one thing that makes reading
            # this field safe.
            my $from = $i - $GUARD_WINDOW < 0 ? 0 : $i - $GUARD_WINDOW;
            next if grep { /is_lattice_type/ } @lines[ $from .. $i ];

            push @readers, "$f:" . ( $i + 1 );
        }
    }

    is \@readers, [],
        'no production code reads ->stamp (see this test for why that matters)'
        or diag(
            "A ->stamp reader appeared. For a statically-OOB Subscript the\n"
          . "type axis currently holds 'Slot', which is NOT a lattice type.\n"
          . "Fix the OOB path to record a real type (Undef) before reading it."
        );
};

done_testing;
