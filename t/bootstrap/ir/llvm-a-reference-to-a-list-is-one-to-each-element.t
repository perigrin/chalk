# ABOUTME: \(@a) in a list is a reference to each element of the array, in order, each
# ABOUTME: the element's own slot: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# \(@a) IS A REFERENCE TO EACH ELEMENT, not to the array (pvm 412, 009). It
# was refused ("a list with a List in it").
for my $c (
    [ q{my @a = (10, 20); my @r = \(@a); print ${$r[0]}, " ", ${$r[1]}, " ", scalar(@r), "\n";}, "10 20 2\n", 'each element, in order' ],
    [ q{my @a = (10, 20); my @r = \(@a); ${$r[1]} = 5; print "@a\n";},                            "10 5\n",    'a store through one reaches the array' ],
) {
    my ($src, $want, $name) = @$c;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# ONE OUTSIDE A LIST is refused, not lowered as `\@a` (perl's is a reference
# to the last element).
{
    eval { through_llvm(q{my @a = (10, 20); my $r = \(@a); print $$r, "\n";}) };
    like($@, qr/GAP: /, 'a \\(@a) as one value is refused');
}

done_testing;
