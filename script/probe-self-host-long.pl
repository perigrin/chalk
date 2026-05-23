# ABOUTME: Targeted re-probe of the 10 files that timed out at 60s in the initial self-host probe.
# ABOUTME: Uses a 600s per-file timeout to distinguish "slow but terminating" from "non-terminating."
use 5.42.0;
use utf8;
use Time::HiRes qw(time);
use Scalar::Util qw(blessed);
use POSIX qw(:sys_wait_h);
use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::MOP;

# Files that timed out in the initial probe at 60s. Ordered smallest-first.
my @files = (
    'lib/Chalk/Bootstrap/Semiring/TypeInference.pm',
    'lib/Chalk/Bootstrap/BNF/Target/C.pm',
    'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm',
    'lib/Chalk/Bootstrap/Semiring/Precedence.pm',
    'lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm',
    'lib/Chalk/Bootstrap/Perl/Target/Perl.pm',
    'lib/Chalk/Bootstrap/Earley.pm',
    'lib/Chalk/Bootstrap/Perl/Target/C.pm',
    'lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm',
    'lib/Chalk/Bootstrap/Perl/Actions.pm',
);

my $TIMEOUT = 600;  # seconds per file

say "Building grammar...";
my $t0 = time;
my $raw = perl_pipeline();
my $bnf = Chalk::Bootstrap::BNF::Target::Perl->new->generate($raw);
my $pkg = 'Chalk::Grammar::Perl::SelfHostLongProbe';
$bnf =~ s/Chalk::Grammar::BNF::Generated/$pkg/g;
eval $bnf;
die "grammar eval failed: $@" if $@;
my $grammar = do { no strict 'refs'; &{"${pkg}::grammar"}(); };
printf "Grammar built in %.1fs\n", time - $t0;
say "Per-file timeout: ${TIMEOUT}s";

my %outcome;
my @details;

for my $i (0..$#files) {
    my $file = $files[$i];
    my $size = -s $file;

    open my $fh, '<:utf8', $file or do {
        say "[$file] IOERROR: $!";
        next;
    };
    my $source = do { local $/; <$fh> };
    close $fh;

    pipe(my $r_fh, my $w_fh) or die "pipe: $!";
    my $start = time;
    my $pid = fork();
    die "fork: $!" unless defined $pid;

    if ($pid == 0) {
        close $r_fh;
        my $result;
        eval {
            my $parser = build_perl_ir_parser($grammar, start => 'Program');
            $parser->semiring->reset_cache;
            my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
            my $parse = $parser->parse_value($source);
            if (!defined $parse) {
                $result = "UNDEF\t";
            } elsif ($parse->is_zero) {
                $result = "ZERO\t";
            } else {
                my $n_classes = scalar grep { $_->name ne 'main' } $mop->classes;
                my $n_methods = 0;
                my $n_subs = 0;
                for my $cls ($mop->classes) {
                    $n_methods += scalar $cls->methods;
                    $n_subs    += scalar $cls->subs;
                }
                $result = "PARSED\tclasses=$n_classes methods=$n_methods subs=$n_subs";
            }
            1;
        } or do {
            my $err = $@ // 'unknown';
            $err =~ s/\n.*//s;
            $err = substr($err, 0, 200);
            $result = "CRASH\t$err";
        };
        print $w_fh ($result // "UNKNOWN\t") . "\n";
        close $w_fh;
        exit 0;
    }

    # Parent
    close $w_fh;
    my $line;
    my $timed_out = 0;
    eval {
        local $SIG{ALRM} = sub { die "TIMEOUT\n" };
        alarm $TIMEOUT;
        $line = <$r_fh>;
        alarm 0;
    };
    if ($@) {
        $timed_out = 1;
        kill 'KILL', $pid;
    }
    waitpid($pid, 0);
    close $r_fh;

    my $elapsed = time - $start;
    my $outcome;
    my $extra = '';
    if ($timed_out) {
        $outcome = 'TIMEOUT';
    } elsif (!defined $line) {
        $outcome = 'CRASH';
        $extra = 'no output from child';
    } else {
        chomp $line;
        ($outcome, $extra) = split /\t/, $line, 2;
        $outcome //= 'UNKNOWN';
        $extra //= '';
    }

    push @details, [$file, $outcome, $elapsed, $extra, $size];
    $outcome{$outcome}++;
    printf "[%d/%d] %-9s %7.1fs %7d  %s%s\n",
        $i+1, scalar @files, $outcome, $elapsed, $size, $file,
        ($extra ? " :: $extra" : '');
}

say "\n## Summary";
say "=" x 60;
for my $cat (sort { $outcome{$b} <=> $outcome{$a} } keys %outcome) {
    my $n = $outcome{$cat};
    printf "  %-9s %d / %d\n", $cat, $n, scalar @files;
}

my $total = 0;
$total += $_->[2] for @details;
printf "\nTotal wall time: %.1fs across %d files\n", $total, scalar @details;
