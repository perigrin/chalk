# ABOUTME: a read of a variable kept in memory, at a loop's memory, is this pass's value even
# ABOUTME: when its user is lowered after the pass's store: B::SoN -> chalk -> lli == perl.
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

# `$p` passed to a sub is kept in memory; `$o .= $p * 10` is lowered as the
# loop's back-edge value, after `$p = g($p)` stored the next pass's: perl's
# 0.10.20. printed 10.20.30. (older; found under pvm 154).
for my $c (
    [ q{sub g { $_[0] + 1 } my $p = 0; my $o = ""; while ($p < 3) { $o .= ($p * 10) . "."; $p = g($p) } print $o, "\n";} ],
    [ q{sub g { $_[0] + 1 } my $s = "abc"; my $p = 0; my $o = ""; while ($p < length $s) { $o .= substr($s, $p, 1) . "."; $p = g($p) } print $o, "\n";} ],
    [ q{sub g { $_[0] + 1 } my $p = 0; my $o = ""; while ($p < 3) { $o .= "<$p>"; $p = g($p) } print "$o $p\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
