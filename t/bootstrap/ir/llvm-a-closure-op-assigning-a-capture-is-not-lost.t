# ABOUTME: a closure that op-assigns what it captured (`$t += 1`) gives perl's answer
# ABOUTME: or is refused by name -- never the write lost: B::SoN -> chalk -> lli.
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

# B::SoN spelled `$t += 1` on a captured $t as Coerce(CellParam -> Num) + 1:
# the cell's reference read as a number, and no CellWrite. chalk lowered it,
# and $t stayed 0 (perl: 7). A CellParam reaching anything but a cell read
# or write is a shape chalk does not know.
for my $src (
    q{my $t = 0; my $add = sub { $t += $_[0] }; $add->(3); $add->(4); print "$t\n";},
    q{my $t = 0; my $f = sub { $t += 1 }; $f->(); print "$t\n";},
    q{my $s = "a"; my $f = sub { $s .= "b" }; $f->(); print "$s\n";},
) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    ok(( defined $got && $got eq $want ) || $@ =~ /GAP/, "perl's answer or refused: $src")
        or diag "got: " . ( $got // 'undef' ) . " want: $want $@";
}

done_testing;
