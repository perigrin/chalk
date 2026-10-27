# ABOUTME: a scalar m//g on a variable matches from its pos() and leaves pos() at the end
# ABOUTME: of the match (undef on a miss): B::SoN -> chalk -> lli == perl.
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


# /g was refused, and pos() had no lowering (pvm 388, 010).
for my $c (
    [ q{my $s = $ENV{X} // "abcabc"; $s =~ m/b/g; my $a = pos($s); pos($s) = 0; $s =~ m/b/g; my $b = pos($s); print "$a $b\n";} ],
    [ q{my $s = "a1b22c333"; my $o = ""; while ($s =~ /(\d+)/g) { $o .= "<$1>" } print "$o\n";} ],
    [ q{my $s = "xaxa"; $s =~ /a/g; my $p1 = pos($s); $s = "aaa"; my $p2 = defined pos($s) ? "d" : "u"; $s =~ /a/g; print "$p1 $p2 ", pos($s), "\n";} ],
    [ q{my $s = "ab"; $s =~ /b/g; my $hit = $s =~ /b/g ? "y" : "n"; print $hit, defined pos($s) ? "d" : "u", "\n";} ],
    # AN s/// AFTER IT follows it as its memory version, not its replacement
    # (the match's 1 replaced "a": 1XbX for perl's AXbX).
    [ q{my $s = "aXbX"; $s =~ /X/g; $s =~ s/a/A/; print defined pos($s) ? "d" : "u", " $s\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
