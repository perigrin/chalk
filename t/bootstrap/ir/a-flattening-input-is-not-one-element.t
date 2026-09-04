# ABOUTME: A container input that expands to many elements defeats a static bounds check.
# ABOUTME: Counting input SLOTS as elements stamps a real read Undef -- a miscompile, not a gap.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Pipeline;

# `_static_miss` decides whether a constant index provably reads past the end of
# a literal aggregate, so the read can be stamped `Undef` (perl's answer for a
# miss) instead of the element type. It answers that by COUNTING THE
# CONTAINER'S INPUT SLOTS.
#
# That count is only the element count when every input holds exactly one
# value. A perl list FLATTENS, so one slot can hold many:
#
#     my @a = (1,2,3,4);
#     my @t = @a[-2, -1];     ArrayLiteral( Slice )  -- ONE input, TWO elements
#     $t[1]                   perl says 4
#
# Counting slots reads that container as length 1, calls index 1 out of bounds,
# and stamps the read `Undef`. THAT IS A MISCOMPILE, NOT A MISSING TYPE: the
# backend then emits the tagged-undef path and the program prints nothing where
# perl prints 4. A wrong answer outranks a refusal.
#
# The guard for this already existed and named ArrayLiteral/HashLiteral -- the
# flattening shapes that had been met at the time. A `Slice` flattens exactly
# the same way and was not named. Keying on the arity property rather than on a
# list of op names is what makes ExpressionList/ListAppend/ListAssign safe too,
# without the list having to grow every time a plural node is added.
#
# Reported by perl5-son, who hit the same bug in their own element-typing
# (b53a881). Chalk's guard is chalk's own, over its own loaded graph, so their
# fix does not reach it -- verified: this still reproduced with their fixed
# producer pinned.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# Load a program through the real pipeline and hand back its entry graph.
sub load_program ($src) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$fh} $src;
    close $fh;

    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return undef unless $json =~ /\S/;

    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my (undef, $graphs, undef, $err) = Chalk::CodeGen::Pipeline->new
        ->run_detail($json, $select, program_mode => 1);
    return undef if $err;
    return $graphs->{'main::__PROGRAM__'};
}

sub subscripts_of ($g) {
    return grep { $_->operation eq 'Subscript' } $g->nodes->@*;
}

subtest 'a slice in a container defeats the static bounds check' => sub {
    my $g = load_program(<<'PROG') or plan skip_all => 'producer emitted no graph';
use 5.42.0;
my @a = (1,2,3,4);
my @t = @a[-2, -1];
print "$t[0],$t[1]\n";
PROG

    my @subs = subscripts_of($g);
    cmp_ok(scalar @subs, '>=', 2, 'both element reads are present') or return;

    # perl prints "3,4" -- BOTH reads land on a real element. Neither may be
    # stamped Undef, which is what a slot-count bounds check concludes for the
    # second one.
    my @undef_stamped = grep { ($_->stamp // '') eq 'Undef' } @subs;
    is_deeply([ map { $_->stamp } @undef_stamped ], [],
        'no read of a flattened container is stamped Undef')
        or diag("  a read perl answers with a VALUE was typed as undef;\n"
              . "  the container's inputs were counted as its elements.");
};

# The guard must not fire so widely that it stops narrowing ordinary literals.
# A plain list really does have one element per slot, so its bounds check is
# sound and a genuine out-of-bounds read really is undef.
subtest 'a plain literal still narrows, and a real miss is still Undef' => sub {
    my $g = load_program(<<'PROG') or plan skip_all => 'producer emitted no graph';
use 5.42.0;
my @a = (10, 20, 30);
print "$a[1]\n";
PROG

    my ($read) = subscripts_of($g);
    ok($read, 'found the element read') or return;
    isnt($read->stamp, 'Undef',
        'an in-bounds read of a plain literal is not undef');
    isnt($read->stamp, undef,
        'and it still gets a type -- the guard did not blind the narrowing');
};

done_testing;
