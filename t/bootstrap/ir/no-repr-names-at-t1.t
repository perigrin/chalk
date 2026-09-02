# ABOUTME: T1 is the type axis; a representation name must never appear in it.
# ABOUTME: `Slot` is an encoding, not a Chalk type, and nothing at T1 may name it.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Grammar::Perl::TypeLibrary;

# THE SEPARATION THIS PINS.
#
# T1 answers "what type is this value" over the Chalk lattice. T2 answers "how
# is it encoded" over LLVM's types. The functor between them exists precisely
# so the two vocabularies can disagree -- `Scalar` is a lattice type whose
# ENCODING is `%Slot`, and `Boolean` is a lattice type whose encoding is `i1`
# that it shares with `Undef`.
#
# `Slot` is a name on the SECOND axis only. It is not a Chalk type: it has no
# parent, no children, and no membership rule. It names the { i1 defined, i8
# tag, i64 payload } cell that `Scalar` encodes as. A T1 pass that branches on
# `Slot` has stopped asking about types and started asking about layout, which
# is the layer violation the functor was built to remove.
#
# Chalk::IR::Node's own comment already draws this line, because the stamp and
# representation fields are currently ONE field under a transitional alias:
#
#     set_stamp('Int')           -> stamp=Int
#     set_representation('Slot') -> stamp=Slot     the Int TYPE would be gone
#
# so a repr name written through that alias does not merely sit in the wrong
# vocabulary -- it DESTROYS the type. That is why this is worth a test rather
# than a convention.

subtest 'Slot is not a member of the lattice' => sub {
    # A lattice member has a place: something above it, or it is the root.
    # `Slot` has neither, and asking makes that concrete rather than implied.
    my @members = qw(Unknown List Scalar Void Undef Str Num Int Boolean
                     VString DualVar Ref Object Regex ScalarRef LValueRef
                     ArrayRef HashRef CodeRef GlobRef Array Hash);

    my $slot_relates = grep {
        Chalk::Grammar::Perl::TypeLibrary::is_subtype('Slot', $_)
            || Chalk::Grammar::Perl::TypeLibrary::is_subtype($_, 'Slot')
    } @members;

    is($slot_relates, 0,
        'Slot is comparable to NO lattice member -- it is not on the lattice');

    # Contrast with Scalar, which is: this is what a real member looks like,
    # and it is the type whose ENCODING Slot names.
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Str', 'Scalar'),
        'Scalar IS on the lattice (Str <: Scalar)');
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Scalar', 'List'),
        'and it has a parent (Scalar <: List) -- Slot has none');
};

# THE REGRESSION GUARD. A T1 file naming a repr is the defect; this catches
# it by reading the source, because a runtime probe cannot reach a table row
# that is currently unreachable.
subtest 'no T1 source names a representation' => sub {
    # T1: the type axis and the passes that compute over it. The LLVM target
    # is T2 and is deliberately excluded -- naming `Slot` is its job.
    my @t1 = qw(
        lib/Chalk/IR/Analysis.pm
        lib/Chalk/IR/Serialize/JSON.pm
        lib/Chalk/Grammar/Perl/TypeLibrary.pm
        lib/Chalk/Bootstrap/Optimizer/DefinedOrFold.pm
        lib/Chalk/Bootstrap/Semiring/FilterComposite.pm
    );

    for my $file (@t1) {
        my @live;
        open my $fh, '<', $file or do { fail("open $file: $!"); next };
        my $n = 0;
        while (my $line = <$fh>) {
            $n++;
            # Comments may name `Slot` freely: explaining the encoding a type
            # maps to is exactly the cross-reference a reader needs, and
            # forbidding it would push the knowledge out of the code entirely.
            next if $line =~ /^\s*#/;
            next unless $line =~ /\bSlot\b/;
            push @live, "$n: " . ($line =~ s/^\s+|\s+$//gr);
        }
        close $fh;

        is_deeply(\@live, [],
            "$file names no representation in live code")
            or diag("  live repr name at:\n    " . join("\n    ", @live));
    }
};

done_testing;
