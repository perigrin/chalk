# ABOUTME: ProgramRunner contract tests: a file is compiled AS ITSELF and judged on
# ABOUTME: stdout AND exit status, and a blocked file names its OWN entry blocker.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::CodeGen::Harness::ProgramRunner;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';
my $BASE = $ENV{PERL5_TBASE_DIR} // "$ENV{HOME}/dev/perl5/t/base";

plan skip_all => "perl 5.42 not found at $PERL"    unless -x $PERL;
plan skip_all => "perl5-son not found at $SON"     unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"           unless -x $LLI;
plan skip_all => "perl5 t/base not found at $BASE" unless -d $BASE;

my $R = 'Chalk::CodeGen::Harness::ProgramRunner';

sub write_prog ($src) {
    my ($fh, $path) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $src;
    close $fh;
    return $path;
}

# --- A real file compiles as itself -----------------------------------------
subtest 'a stock t/base file compiles AS ITSELF and matches perl' => sub {
    my $r = $R->run_file("$BASE/if.t");
    is($r->{verdict}, 'PASS', 'if.t PASSes')
        or diag("blocker: " . ($r->{skip_reason} // '(none)'));
    is($r->{lli_stdout}, $r->{perl_stdout}, 'stdout matches perl exactly');
    is($r->{lli_exit},   $r->{perl_exit},   'exit status matches perl');
    like($r->{perl_stdout}, qr/^1\.\.2\n/, 'the oracle is real TAP, not empty')
        or diag('an empty-vs-empty comparison would pass vacuously');
};

# --- THE CONTRACT DISCRIMINATOR ---------------------------------------------
# Exit status is part of the contract. The wrapped contract this replaced could
# not express this test at all: it read ANY nonzero lli exit as failure-to-lower
# (Mode1Runner.pm:167, deleted), so a program whose correct behavior is a
# nonzero exit was unscoreable, and a program that exited wrongly was
# indistinguishable from one that failed to compile.
#
# `die` must exit 255 with an empty stdout tail; the runner must compare that
# against perl rather than treating it as a toolchain error.
subtest 'exit status is compared, not swallowed' => sub {
    my $r = $R->run_file(write_prog(qq{print "before\\n"; die "boom\\n";\n}));
    is($r->{perl_exit}, 255, 'the oracle really does exit 255 (die)');
    isnt($r->{verdict}, 'SKIP',
        'a nonzero exit is NOT reported as failure-to-lower')
        or diag("reported as SKIP: " . ($r->{skip_reason} // '(none)'));
    is($r->{verdict}, 'PASS', 'stdout and exit status both match perl');
    is($r->{lli_exit}, 255, 'the compiled program exits 255 too');
};

# --- No source rewriting ----------------------------------------------------
# The file is handed to the producer unmodified. A file whose only entry point
# is its own top level must be found, not supplied: the wrapped contract passed
# such a file by rewriting it into `sub __main__`, which measured the wrapper.
subtest 'the entry point is discovered, not supplied' => sub {
    my $r = $R->run_file(write_prog(qq{print "hi\\n";\n}));
    is($r->{verdict}, 'PASS', 'a bare top-level program compiles');
    is($r->{lli_stdout}, "hi\n", 'and prints exactly what perl prints');
};

# --- A blocked file names its OWN blocker -----------------------------------
subtest 'a blocked file names the ENTRY graph blocker' => sub {
    my $r = $R->run_file("$BASE/rs.t");
    is($r->{verdict}, 'SKIP', 'rs.t does not compile yet');
    like($r->{skip_reason}, qr/explicit filehandle/,
        'it names main::__PROGRAM__\'s own blocker');
    unlike($r->{skip_reason}, qr/if\/else arm/,
        'not main::test_bad_setting\'s, which the producer prints FIRST');
};

# --- No silent drops --------------------------------------------------------
subtest 'a SKIP always carries a named reason' => sub {
    my %hist;
    my $r = $R->run_file_into_histogram(\%hist, "$BASE/while.t");
    is($r->{verdict}, 'SKIP', 'while.t does not compile yet');
    ok(defined $r->{skip_reason} && length $r->{skip_reason},
        'the skip names a blocker');
    is($hist{ $r->{skip_reason} }, 1, 'and it is counted in the histogram');
};

done_testing();
