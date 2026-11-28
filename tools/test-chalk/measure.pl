#!/usr/bin/perl
# ABOUTME: Test::Chalk's measure: chalk's tests through B::SoN, T2 and lli against perl (TapDiff),
# ABOUTME: one verdict per file; writes the verdicts and ranks the refusals.
#
#   cwd = chalk root
#   HOME=/home/runner PERL5_SON_LIB=<B::SoN>/lib LLI=/usr/bin/lli; ulimit -v 4000000
#   perl tools/test-chalk/measure.pl --out DIR [--easy] [--jobs 2] [--timeout 240] [FILE.t ...]
#
# THE METHOD of docs/plans/2026-11-17-test-chalk-measured.md, Part B, whose
# scripts were never committed:
#   - what is measured: every test that uses Test::Chalk (all of chalk's since
#     the 11-17 migration), or Test::More, swapped; --easy keeps only those
#     calling none of the hard-tier names, 11-17's denominator;
#   - the swap, for a Test::More file: `use Test::Chalk` for `use Test::More`,
#     and `use lib 'lib', 't/lib';` so the copy needs no `prove -l`;
#   - the compare: t/lib/Chalk/CodeGen/Harness/TapDiff.pm on the copy, killed
#     by `timeout` past the budget (a B::SoN hang is a TIMEOUT, not a wait).
# Writes DIR/verdicts.tsv (file, verdict, why) and DIR/copies/; prints the
# counts and the refusals ranked by reason. Rerunning with the same DIR
# resumes: a file with a verdict is not run again.
package TestChalkMeasure;
use v5.42.0;
use Getopt::Long;
use File::Find;
use File::Path qw(make_path);

my @HARD = qw(use_ok require_ok like unlike is_deeply cmp_ok skip todo todo_skip eq_array eq_hash
              eq_set TODO can_ok isa_ok new_ok explain subtest);
my $HARD = join '|', @HARD;

# measured($source) -> true for a test using Test::Chalk, or Test::More (swapped)
sub measured ($src) { return $src =~ /^\s*use\s+Test::(?:Chalk|More)\b/m ? 1 : 0 }

# is_easy($source) -> true for a measured test calling only easy-tier names
sub is_easy ($src) {
    return 0 unless measured($src);
    ( my $code = $src ) =~ s/#.*$//mg;   # (a name in a comment calls nothing)
    $code =~ s/^\s*use\s+Test::(?:Chalk|More)\b.*$//mg;
    return $code =~ /\b(?:$HARD)\b/ ? 0 : 1;
}

# swap($source) -> the copy: Test::Chalk for Test::More, lib/ and t/lib/ found;
# a Test::Chalk file as it is
sub swap ($src) {
    return $src unless $src =~ /^\s*use\s+Test::More\b/m;
    $src =~ s/^(\s*)use\s+Test::More\b/${1}use Test::Chalk/mg;
    my $lib = "use lib 'lib', 't/lib';\n";
    return $src =~ s/\A(#![^\n]*\n)/$1$lib/r if $src =~ /\A#!/;
    return $lib . $src;
}

sub _slurp ($f) { open my $fh, '<', $f or die "$f: $!"; local $/; return <$fh> }

sub main (@argv) {
    local @ARGV = @argv;
    my ( $out, $easy, $jobs, $timeout ) = ( undef, 0, 2, 240 );
    GetOptions( 'out=s' => \$out, 'easy' => \$easy, 'jobs=i' => \$jobs, 'timeout=i' => \$timeout )
        && $out or die "usage: $0 --out DIR [--easy] [--jobs N] [--timeout SECS] [FILE.t ...]\n";
    die "run from chalk's root\n" unless -f 't/lib/Chalk/CodeGen/Harness/TapDiff.pm';
    my @files = @ARGV;
    find( { no_chdir => 1, wanted => sub { push @files, $_ if /\.t\z/ && -f } }, 't' ) unless @files;
    @files = sort grep { my $src = _slurp($_); $easy ? is_easy($src) : measured($src) } @files;
    make_path("$out/copies", "$out/runs");

    my %pid;
    my $reap = sub { my $p = waitpid( -1, 0 ); delete $pid{$p} if $p > 0 };
    for my $f (@files) {
        ( my $id = $f ) =~ tr{/.}{__};
        next if -s "$out/runs/$id";   # (resume: this one has its verdict)
        my $copy = "$out/copies/$id.t";
        open my $c, '>', $copy or die "$copy: $!";
        print $c swap( _slurp($f) );
        close $c;
        $reap->() while keys %pid >= $jobs;
        my $pid = fork // die "fork: $!";
        if ( !$pid ) {
            my $line = qx(timeout $timeout $^X -Ilib -It/lib t/lib/Chalk/CodeGen/Harness/TapDiff.pm $copy 2>/dev/null);
            my $rc = $? >> 8;
            my ( $v, undef, $why ) = split /\t/, ( $line // '' ) =~ s/\n.*//sr, 3;
            ( $v, $why ) = ( 'TIMEOUT', "no verdict within ${timeout}s" ) if $rc == 124;
            ( $v, $why ) = ( 'CRASH', "the harness exited $rc with no verdict" ) unless $v;
            open my $o, '>', "$out/runs/$id" or exit 1;
            print $o join( "\t", $f, $v, $why // '' ), "\n";
            exit 0;
        }
        $pid{$pid} = $f;
    }
    $reap->() while keys %pid;

    my ( %n, %why );
    open my $tsv, '>', "$out/verdicts.tsv" or die $!;
    print $tsv "file\tverdict\twhy\n";
    for my $f (@files) {
        ( my $id = $f ) =~ tr{/.}{__};
        open my $r, '<', "$out/runs/$id" or next;
        my $row = <$r>;
        print $tsv $row;
        chomp $row;
        my ( undef, $v, $why ) = split /\t/, $row, 3;
        $n{$v}++;
        $why{$why}++ if $v ne 'SAME';
    }
    close $tsv;
    say( ( $easy ? 'easy-tier' : 'measured' ) . ' files: ' . scalar(@files) );
    say join ' ', map {"$_=$n{$_}"} sort keys %n;
    say "\nnot SAME, by reason:";
    printf "%5d  %s\n", $why{$_}, $_ for grep { defined } ( sort { $why{$b} <=> $why{$a} || $a cmp $b } keys %why )[ 0 .. 29 ];
    say "\n$out/verdicts.tsv";
    return ( $n{DIFFERS} // 0 ) ? 1 : 0;
}

exit main(@ARGV) unless caller;
1;
