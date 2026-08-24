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

subtest 'PRECONDITION: nothing in lib/ reads the type axis' => sub {
    # THE LOAD-BEARING FACT. The loader writes `Slot` into the shared field for
    # a statically out-of-bounds Subscript (Serialize/JSON.pm:1459), and `Slot`
    # is not a member of the type lattice. Every provably-OOB element read
    # therefore has a corrupted type axis after loading.
    #
    # That is harmless only while NO consumer reads ->stamp. The first one
    # added will read `Slot` and be wrong -- the honest type is `Undef`, since
    # an OOB read yields perl's undef, with `Slot` being the lowering pass's
    # encoding choice.
    #
    # So: fail here, loudly, the moment a production ->stamp reader appears.
    # Fixing this test means fixing the OOB path to write a TYPE, not deleting
    # the assertion.
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

    for my $f (@files) {
        # Chalk::IR::Node itself defines the accessors; it is not a consumer.
        next if $f eq 'lib/Chalk/IR/Node.pm';
        open my $fh, '<', $f or next;
        while (my $line = <$fh>) {
            next if $line =~ /^\s*#/;              # comments are not readers
            next unless $line =~ /->stamp\b/;
            next if $line =~ /->stamp\s*\(/;       # a call, not the reader
            push @readers, "$f:$.";
        }
        close $fh;
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
