# ABOUTME: Parse-only probe — runs the bootstrap parser over every lib/*.pm and classifies outcomes.
# ABOUTME: Validates IR-layer readiness for self-hosting; not a full self-hosting attempt (no codegen, no eval).
use 5.42.0;
use utf8;
use File::Find;
use Time::HiRes qw(time);
use Scalar::Util qw(blessed);
use POSIX qw(:sys_wait_h);
use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::MOP;

# Build the grammar once.
say "Building grammar...";
my $t0 = time;
my $raw = perl_pipeline();
my $bnf = Chalk::Bootstrap::BNF::Target::Perl->new->generate($raw);
my $pkg = 'Chalk::Grammar::Perl::SelfHostProbe';
$bnf =~ s/Chalk::Grammar::BNF::Generated/$pkg/g;
eval $bnf;
die "grammar eval failed: $@" if $@;
my $grammar = do { no strict 'refs'; &{"${pkg}::grammar"}(); };
printf "Grammar built in %.1fs\n", time - $t0;

# Collect all .pm files under lib/.
my @files;
find(sub {
    return unless -f && /\.pm$/;
    push @files, $File::Find::name;
}, 'lib');

@files = sort { -s $a <=> -s $b } @files;  # smallest first; bigger files later
say "Found ", scalar @files, " .pm files under lib/";

# Per-file outcome buckets.
my %outcome;          # outcome => count
my @details;          # arrayref of (file, outcome, elapsed_s, extra_info)

# Per-file parse, with a per-file timeout enforced by fork.
my $TIMEOUT = 60;   # seconds per file

for my $i (0..$#files) {
    my $file = $files[$i];
    my $size = -s $file;

    open my $fh, '<:utf8', $file or do {
        push @details, [$file, 'IOERROR', 0, "$!"];
        $outcome{IOERROR}++;
        next;
    };
    my $source = do { local $/; <$fh> };
    close $fh;

    # Fork to enforce per-file wall-clock timeout. The child runs the parse
    # and writes outcome to a pipe. The parent waits with an alarm.
    pipe(my $r_fh, my $w_fh) or die "pipe: $!";

    my $start = time;
    my $pid = fork();
    if (!defined $pid) {
        die "fork: $!";
    }
    if ($pid == 0) {
        # Child
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
                # Try to extract some MOP shape info.
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

    # Parent — wait for child with timeout
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

    printf "[%3d/%d] %-9s %6.2fs %7d  %s%s\n",
        $i+1, scalar @files, $outcome, $elapsed, $size, $file,
        ($extra ? " :: $extra" : '');
}

# Summary
say "\n## Summary";
say "=" x 60;
my $total = scalar @files;
for my $cat (sort { $outcome{$b} <=> $outcome{$a} } keys %outcome) {
    my $n = $outcome{$cat};
    printf "  %-9s %4d / %d (%.0f%%)\n", $cat, $n, $total, 100*$n/$total;
}

# Show samples per category (up to 5 per outcome).
say "\n## Samples by outcome";
say "=" x 60;
my %samples;
for my $d (@details) {
    my ($file, $outcome, $elapsed, $extra, $size) = $d->@*;
    push $samples{$outcome}->@*, $d if @{$samples{$outcome} //= []} < 5;
}
for my $cat (sort keys %samples) {
    say "\n### $cat (showing up to 5)";
    for my $d ($samples{$cat}->@*) {
        my ($file, $outcome, $elapsed, $extra, $size) = $d->@*;
        printf "  %6.2fs %7d  %s%s\n", $elapsed, $size, $file,
            ($extra ? " :: $extra" : '');
    }
}

# Wall-clock totals.
my $total_elapsed = 0;
$total_elapsed += $_->[2] for @details;
printf "\nTotal parse wall time: %.1fs across %d files (avg %.2fs/file)\n",
    $total_elapsed, scalar @details, $total_elapsed / scalar(@details || 1);
