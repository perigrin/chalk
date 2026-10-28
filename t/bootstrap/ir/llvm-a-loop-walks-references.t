# ABOUTME: a loop phi carrying a reference (a walk down a linked structure) is
# ABOUTME: a Scalar each reference is boxed into by its tag.
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


# "a loop phi read as a Scalar carries a HashRef" (pvm 138), and ref() of
# the walk's untyped variable (pvm 221).
for my $src (
    q{use v5.42; sub find ($n) { my $cur = $n; while (defined $cur) { if (ref $cur eq 'ARRAY') { return $cur->[0] eq 'x' ? 'found' : 'other' } if (ref $cur eq 'HASH') { $cur = $cur->{next}; next; } return 'stop'; } return 'end'; } print find({ next => { next => ['x'] } }), " ", find({ next => 5 }), " ", find({ next => undef }), "\n";},
    q{sub f { my ($c) = @_; my ($name, $base); my $k = 0; while ($k++ < 5) { if (ref $c eq 'HASH') { $name = $c->{n}; my $a = $c->{a}; $base = $a->[0] if @$a > 0; last } $c = { n => "x", a => [] } } return ($name // 'u') . ($base // 'u') } print f({ n => "e", a => ["b"] }), f(1), "\n";},
) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $want = qx($^X $pl 2>/dev/null);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
