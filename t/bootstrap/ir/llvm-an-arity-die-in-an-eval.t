# ABOUTME: a call with too few or too many arguments for its signature, inside
# ABOUTME: an eval nothing reads $@ of, dies there and the eval catches it.
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


# The arity die was refused even where an eval catches it unread (pvm 060).
for my $src (
    q{use v5.36; package O { sub collapse ($, $phi) { return "c$phi" } } print O->collapse(7), " ", (eval { O->collapse(); 1 } ? "ran" : "too few"), "\n";},
    q{use v5.36; sub g ($k) { return $k } print eval { g(1, 2); 1 } ? "ran" : "too many", " ", g(3), "\n";},
) {
    my $want = qx($^X -e '$src' 2>/dev/null);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# $@ read: its message names the file and line.
my $src = q{use v5.36; sub g ($k) { return $k } eval { g(1, 2); 1 }; print $@ ? "died\n" : "ok\n";};
my $got = eval { through_llvm($src) };
like($@, qr/GAP/, "refused by name: $src") or diag "got: ", $got // '';

done_testing;
