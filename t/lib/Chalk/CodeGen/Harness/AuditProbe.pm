# ABOUTME: Runs the IR audit's probe programs (t/data/audit-probes/*.pl) through B::SoN,
# ABOUTME: chalk's T2 and lli, judging each against perl: SAME, REFUSED, LOUD, WRONG or TIMEOUT.
package Chalk::CodeGen::Harness::AuditProbe;
use v5.42.0;
use File::Temp qw(tempdir);
use Exporter 'import';
our @EXPORT_OK = qw(probes run_probe run_all read_baseline write_baseline $DIR $BASELINE);

our $DIR      = 't/data/audit-probes';
our $BASELINE = "$DIR/BASELINE.tsv";
my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->path;

# The verdicts:
#   SAME     chalk's program printed what perl printed, and ended as perl did:
#            the same exit status (a die is 255, `exit 3` is 3), not only
#            "failed" for both (audit 2026-11-22, risk 11)
#   REFUSED  chalk (or B::SoN) declined the program, naming why
#   LOUD     chalk's program stopped with an error where perl's did not
#   WRONG    it ran and printed something else -- the one verdict nothing may have
#   TIMEOUT  chalk did not finish lowering in time
sub probes () { return sort glob "$DIR/*.pl" }

sub _one_line ($s) { $s =~ s/\s+at \S+ line \d+\.?\s*\z//; $s =~ s/\s+/ /g; $s =~ s/0x[0-9a-f]+/0x.../g; return substr( $s, 0, 160 ) =~ s/\s+\z//r }

# run_probe($file) -> [verdict, why]. Call it in a child process: it loads chalk.
sub run_probe ($file) {
    my $dir  = tempdir( CLEANUP => 1 );
    my $want = qx($^X $file 2>/dev/null </dev/null);
    my $want_st = $?;
    my $want_ok = $want_st == 0;
    require Chalk::CodeGen::Harness::Producer;
    my $wire = Chalk::CodeGen::Harness::Producer->wire_option;
    my $json = qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN$wire $file 2>$dir/son.err);
    unless ( $json =~ /\S/ ) {
        my $why = do { local ( @ARGV, $/ ) = "$dir/son.err"; <> } // '';
        return [ 'REFUSED', 'B::SoN: ' . _one_line($why) ];
    }
    require Chalk::CodeGen::Pipeline;
    my $select = sub ( $graphs, $mop ) {
        my $g   = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0]              or return ();
        return ( [ 'main::__PROGRAM__', $ret ] );
    };
    my ( $units, undef, undef, $err ) = eval { Chalk::CodeGen::Pipeline->new->run_detail( $json, $select, program_mode => 1 ) };
    $err //= $@ if $@;
    return [ 'REFUSED', 'load: ' . _one_line($err) ] if $err;
    # (B::SoN skipped the program: say why in its words -- re-audit 2026-11-23)
    my $u = ( $units // [] )->[0] or do {
        my $err = do { local ( @ARGV, $/ ) = "$dir/son.err"; <> } // '';
        return [ 'REFUSED', 'B::SoN: ' . _one_line($1) ] if $err =~ /skipped main::__PROGRAM__: (.*)/;
        # (perl itself did not compile it: st3, `isa` with no feature for it)
        return [ 'REFUSED', 'perl: the program does not compile: ' . _one_line( ( grep { !/had compilation errors/ } split /\n/, $err )[0] // '' ) ]
            if $err =~ /had compilation errors|syntax error/;
        return [ 'REFUSED', 'no program graph' ];
    };
    return [ 'REFUSED', _one_line( $u->{err} // 'lowering failed' ) ] unless $u->{ok};
    open my $l, '>', "$dir/p.ll" or die $!;
    binmode $l, ':utf8';
    print $l $u->{ll};
    close $l;
    my $got    = qx(timeout 30 $LLI $dir/p.ll 2>$dir/lli.err </dev/null);
    my $got_st = $?;
    my $got_ok = $got_st == 0;
    return [ 'SAME', '' ] if $got eq $want && $got_st == $want_st;
    return [ 'WRONG', 'never ends' ] if ( $got_st >> 8 ) == 124;
    if ( !$got_ok && $want_ok ) {
        my $why = do { local ( @ARGV, $/ ) = "$dir/lli.err"; <> } // '';
        return [ 'LOUD', _one_line($why) ];
    }
    return [ 'WRONG', _one_line( "got=[$got] want=[$want]" . ( $got_st == $want_st ? '' : " (exit status $got_st, perl's $want_st)" ) ) ];
}

# run_all(\@files, jobs => 2, timeout => 180) -> { name => [verdict, why] }:
# one child per probe, so no probe shares chalk state with another and a
# hung lowering is killed by its own alarm.
sub run_all ( $files, %opt ) {
    my $jobs    = $opt{jobs}    // $ENV{AUDIT_JOBS} // 2;
    my $timeout = $opt{timeout} // 180;
    require Chalk::CodeGen::Pipeline;    # loaded once, inherited by each child
    my $dir = tempdir( CLEANUP => 1 );
    my ( %pid, %res );
    my $reap = sub {
        my $pid  = wait;
        my $name = delete $pid{$pid} // return;
        if ( open my $in, '<', "$dir/$name" ) {
            chomp( my $line = <$in> // '' );
            $res{$name} = [ split /\t/, $line, 2 ] if $line =~ /\S/;
        }
        $res{$name} //= [ 'TIMEOUT', "no verdict within ${timeout}s (or the lowering crashed)" ];
        $res{$name}[1] //= '';
    };
    for my $file ( $files->@* ) {
        ( my $name = $file ) =~ s{.*/}{};
        $name =~ s/\.pl\z//;
        $reap->() while keys %pid >= $jobs;
        my $pid = fork // die "fork: $!";
        if ( !$pid ) {
            alarm $timeout;
            my $r = eval { run_probe($file) } // [ 'REFUSED', 'harness: ' . _one_line("$@") ];
            open my $o, '>', "$dir/$name" or exit 1;
            print $o join( "\t", $r->@* ), "\n";
            close $o;
            exit 0;
        }
        $pid{$pid} = $name;
    }
    $reap->() while keys %pid;
    return \%res;
}

sub read_baseline ( $file = $BASELINE ) {
    my %b;
    open my $in, '<', $file or return \%b;
    while (<$in>) {
        chomp;
        next if /^#/ || !/\S/;
        my ( $name, $verdict, $why ) = split /\t/, $_, 3;
        $b{$name} = [ $verdict, $why // '' ];
    }
    return \%b;
}

sub write_baseline ( $res, $file = $BASELINE ) {
    open my $o, '>', $file or die "$file: $!";
    print $o "# The audit probes' verdicts (tools/audit-probes.pl --update writes this file).\n";
    print $o "# name\tverdict\twhy\n";
    print $o join( "\t", $_, $res->{$_}->@* ), "\n" for sort keys $res->%*;
    close $o;
}

1;
