# ABOUTME: exit with a string or a non-integer status exits with its integer value, as perl
# ABOUTME: does: B::SoN -> chalk -> lli exit code == perl's.
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
sub ll_of ($src) {
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
    return ($out, $? >> 8);
}

# exit of a Str (or a Num) status was refused (pvm 064).
for my $src (
    q{my $c = $ENV{NO_SUCH} // "3"; print "ran\n"; exit $c;},
    q{my $c = $ENV{NO_SUCH} // 2.7; exit $c;},
    q{my $c = $ENV{NO_SUCH} // "1e1"; exit $c;},
    q{my $c = $ENV{NO_SUCH} // "abc"; exit $c;},
    q{my $c = $ENV{NO_SUCH} // 0; print "ran\n"; eval { exit $c }; print "trapped\n";},
) {
    my $want = qx($^X -e '$src' 2>/dev/null);
    my $want_rc = $? >> 8;
    my ($got, $rc) = eval { ll_of($src) };
    is("$rc:" . ($got // ''), "$want_rc:$want", "perl's exit and output for $src") or diag $@;
}

done_testing;
