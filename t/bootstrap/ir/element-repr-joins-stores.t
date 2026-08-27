# ABOUTME: A container's element repr joins its literal initializers with every
# ABOUTME: element STORE's rhs, so a type-changing store is visible to inference.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use Scalar::Util qw(blessed);
use lib 'lib', 't/lib';

use Chalk::IR::Serialize::JSON ();
use Chalk::CodeGen::Harness::ProgramRunner;

# `my @arr=(1,2); $arr[0]="hello"; say $arr[0];`
#
# _element_repr derives the element type from the ArrayRef's literal
# initializers alone, so it reads Int -- and the post-store Subscript is
# stamped Int while the value living there is a Str. The backend refuses
# (Context.pm's Assign(Array-lvalue) repr guard) rather than emit the silent
# miscompile. The element repr must be the JOIN of the initializers and every
# store's rhs: Int join Str = Str.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

my $SRC = <<'SRC';
use 5.42.0;
my @arr = (1, 2);
$arr[0] = "hello";
say($arr[0]);
SRC

my ($fh, $path) = tempfile(SUFFIX => '.pl', UNLINK => 1);
binmode $fh, ':utf8';
print $fh $SRC;
close $fh;

my $json = qx($PERL -I$SON -MO=SoN,json $path 2>/dev/null);
plan skip_all => 'producer emitted no JSON' unless ($json // '') =~ /\S/;

my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
my ($g) = grep { defined }
    $graphs->@{ 'main::__PROGRAM__', 'main::__main__' };
plan skip_all => 'no entry graph' unless $g;

my @nodes = $g->nodes->@*;
my @subs  = grep { $_->operation eq 'Subscript' } @nodes;

subtest 'the post-store element read is stamped Str' => sub {
    ok(scalar @subs, 'the probe has element reads');
    is($_->representation, 'Str',
        'Subscript over a container with a Str store reads a Str') for @subs;
};

subtest 'no Coerce wraps the element read' => sub {
    # An Int-stamped read forced to Str print grows a Coerce(Int->Str) in
    # front. Once the element repr IS Str there is nothing to widen.
    my @coerce = grep {
        $_->operation eq 'Coerce'
            && grep { blessed($_) && $_->can('operation')
                        && $_->operation eq 'Subscript' } ($_->inputs // [])->@*
    } @nodes;
    is(scalar @coerce, 0, 'nothing widens the element read');
};

# The typing is now right; LOWERING it is a separate, unbuilt capability.
#
# A %Slot is { i1 defined, i64 payload } -- ONE UNTYPED WORD, with no per-slot
# tag. The read is told how to unbox by its STAMP, and the stamp this join
# produces is a property of the CONTAINER, not of the slot. So for a container
# whose elements genuinely differ -- `my @a=(1,2); $a[0]="hello"; say $a[1];`
# -- a container-wide Str tells the untouched slot 1 to unbox the integer 2 as
# a %StrPair pointer. Measured: SIGSEGV (exit 139) where perl prints 2.
#
# Lowering a heterogeneous container therefore needs what the element-store
# TODO in ir/llvm-aggregate-latent-fixes.t already names: a coercion bridging
# each element that does not conform, so every slot really does hold the
# encoding the container-wide stamp advertises. Until that exists the backend's
# Assign(Array-lvalue) repr guard must keep refusing -- the GAP is correct, and
# relaxing it on the strength of the join alone trades a refusal for a
# segfault.
subtest 'lowering the store is still a GAP -- correctly' => sub {
    my $r = Chalk::CodeGen::Harness::ProgramRunner->run_file($path);
    is($r->{perl_stdout}, "hello\n", 'perl oracle says what this test claims');
    is($r->{verdict}, 'SKIP', 'chalk refuses rather than miscompiling');
    like($r->{skip_reason} // '', qr/GAP: Assign\(Array-lvalue\)/,
        'and refuses at the element-store repr guard, not somewhere else');
};

# WHY THE GUARD MAY NOT SIMPLY BE RELAXED -- the measurement, kept.
#
# The tempting next step is "the join reports Str, so let the store box a Str".
# It was tried and it SEGFAULTS, because the join is container-wide and the
# encoding is per-slot: slot 1 was never stored into and still holds the
# integer 2, but a container-wide Str stamp tells its read to unbox that 2 as a
# %StrPair pointer. This subtest pins the untouched-slot read so a future
# relaxation cannot land without also bridging the non-conforming elements.
subtest 'a read of an UNTOUCHED slot is what makes this unsound to wave through'
=> sub {
    my $src = <<'SRC';
use 5.42.0;
my @arr = (1, 2);
$arr[0] = "hello";
say($arr[1]);
SRC
    my ($h, $p2) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $h, ':utf8';
    print $h $src;
    close $h;

    my $r = Chalk::CodeGen::Harness::ProgramRunner->run_file($p2);
    is($r->{perl_stdout}, "2\n",
        'perl reads the untouched slot as the Int it still holds');
    isnt($r->{verdict}, 'FAIL',
        'chalk does not MISCOMPILE it (a relaxed guard segfaults here)');
};

done_testing;
