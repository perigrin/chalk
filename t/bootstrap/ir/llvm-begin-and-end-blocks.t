# ABOUTME: a BEGIN block runs before the program, in order; an END block after it, last
# ABOUTME: first: B::SoN -> chalk -> lli == perl.
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


# BEGIN and END blocks with effects were refused at load (pvm 258).
for my $src (
    q{END { print "end\n" } BEGIN { print "begin\n" } print "main\n";},
    q{print "m\n"; BEGIN { print "b1\n" } END { print "e1\n" } BEGIN { print "b2\n" } END { print "e2\n" }},
) {
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# AN EXIT OR A DIE RUNS THE END BLOCKS TOO, a die in a sub included:
# lowered after the main line they were missed there.
for my $src (
    q{sub f { die "x\n" if $_[0] } END { print "end\n" } print "m\n"; f(1);},
    q{END { print "end\n" } print "main\n"; exit 3 unless $ENV{NO_SUCH}; print "more\n";},
    q{END { print "e\n"; exit 4 } print "m\n";},
) {
    my $want = qx($^X -e '$src' 2>/dev/null) . ( $? >> 8 );
    my $got = eval { through_llvm($src) };
    my $rc = $@ =~ /lli exited (\d+): (.*)/s ? $1 : 0;
    $got //= $2 // '';
    is($got . $rc, $want, "perl's output and exit for $src") or diag $@;
}

# A BLOCK READING A MAIN-LINE LEXICAL read it unbound: refused.
for my $src (q{my $x; BEGIN { $x = 5 } print defined $x ? $x : "u", "\n";}, q{my $c = 3; END { print "c=$c\n" } print "m\n";}) {
    my $got = eval { through_llvm($src) };
    ok(!defined $got && $@ =~ /GAP/, "refused: $src") or diag $got // $@;
}

done_testing;
