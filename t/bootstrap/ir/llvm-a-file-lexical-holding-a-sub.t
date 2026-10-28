# ABOUTME: a file lexical that only ever holds one anonymous sub is called
# ABOUTME: from a sub as that sub; any other use of the variable is refused.
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


# The store of the code reference was refused (pvm 399).
for my $src (
    q{my $show = sub { return "[@_]" }; sub outer { return "amp=" . &$show . " paren=" . &$show(); } print outer("x", "y"), "\n"; print $show->(), "\n";},
    q{my $f = sub { 2 * $_[0] }; sub g { return "<" . $f->($_[0]) . ">" } print g(4), " ", g(10), "\n";},
) {
    my $want = qx($^X -e '$src' 2>&1);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# Which sub it holds is not one store's: refused.
for my $src (
    q{my $f = sub { 1 }; $f = sub { 2 } if @ARGV; sub g { return $f->() } print g(), "\n";},
    q{my $f = sub { 1 }; my $r = \$f; sub g { return $f->() } print g(), "\n";},
    q{my $n = 3; my $f = sub { $n }; sub g { return $f->() } print g(), "\n";},
) {
    my $got = eval { through_llvm($src) };
    like($@, qr/GAP/, "refused by name: $src") or diag "got: ", $got // '';
}

done_testing;
