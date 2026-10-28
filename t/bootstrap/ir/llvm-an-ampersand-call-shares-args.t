# ABOUTME: `&name;` calls name with its caller's own @_: empty at the top
# ABOUTME: level, the inlined caller's arguments in a sub; a shift refused.
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


# `&f` had no lowering at all (pvm 008 399).
for my $src (
    q{sub answer { 42 } print &answer, " ", &answer(), "\n";},
    q{sub f { return "[@_]" } sub outer { return &f } print outer("x", "y"), "\n";},
    q{sub f { return $_[1] } sub outer { return &f . "|" . f(7) } print outer(3, 4), "\n";},
) {
    my $want = qx($^X -e '$src' 2>&1);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A shift on either side changes the @_ the other sees.
for my $src (
    q{sub f { return "[@_]" } sub outer { my $a = shift; return &f } print outer(1, 2), "\n";},
    q{sub f { return shift } sub outer { return &f . "@_" } print outer(1, 2), "\n";},
) {
    my $got = eval { through_llvm($src) };
    like($@, qr/GAP/, "refused by name: $src") or diag "got: ", $got // '';
}

done_testing;
