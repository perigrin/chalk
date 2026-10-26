# ABOUTME: a reference to a my variable taken in a loop body names that pass's
# ABOUTME: variable (perl makes a fresh one each pass): perl's answer, or refused.
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

# chalk keeps one location per lexical, so every pass's \$x named the same
# one: the last pass's value, printed for every element (pvm 219).
for my $c (
    [ q{my @l; for my $i (0, 1) { my $x = $i + 1; $l[$i] = \$x } print join(",", map { $$_ } @l), "\n";} ],
    [ q{my @l; for my $i (0, 1) { my $x = $i + 1; push @l, \$x } print ${ $l[0] }, ${ $l[1] }, "\n";} ],
    [ q{my @l; my $i = 0; while ($i < 2) { my $x = $i; push @l, \$x; $i++ } print ${ $l[0] }, ${ $l[1] }, "\n";} ],
    [ q{my @l = map { my $x = $_; \$x } 1, 2; print ${ $l[0] }, ${ $l[1] }, "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, $want, "perl's answer for $src") }
    else {
        # Refused where it is made: by chalk, or by B::SoN (on its stderr).
        my $why = $@ =~ /GAP:/ ? $@ : qx($^X -I$SON -MO=-q,SoN,json -e '$src' 2>&1);
        like($why, qr/GAP:/, "refused by name: $src");
    }
}

done_testing;
