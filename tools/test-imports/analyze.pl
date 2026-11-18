#!/usr/bin/env perl
# analyze.pl RUNSDIR WORKTREE OUT_DETAIL OUT_SUMMARY OUT_REPORT
# Reads INCdump output (*.inc) and run metadata (*.meta) for every test, writes
# one row per test x module, one row per test, and a text report (core, gateways, artifacts).
use v5.42;
use Config;
use List::Util qw(sum0 max);
use Cwd qw(abs_path);

my ( $R, $WT, $OD, $OS, $OR ) = @ARGV;
chdir $WT or die;
my @CORE = map { $Config{$_} } qw(privlib archlib);
my @SITE = map { $Config{$_} } qw(sitelib sitearch);
my $SON  = $ENV{PERL5_SON_LIB} // '/home/user/repo/lib';
my $WTA  = abs_path('.');

sub norm_path ($p) {
    return $p if $p =~ /\A(?:REF:|UNDEF|\(eval|-e\z)/;
    $p =~ s{\A\Q$WTA\E/}{};
    $p =~ s{\A\./}{};
    $p =~ s{/\./}{/}g;
    1 while $p =~ s{[^/]+/\.\./}{};
    return $p;
}

sub loc_class ($p) {
    return 'unknown' if $p =~ /\A(?:REF:|UNDEF)/;
    return 'chalk'   if $p =~ m{\A(?:lib/Chalk/|lib/Chalk\.pm)};
    return 'harness' if $p =~ m{\At/(?:bootstrap/)?lib/} || $p =~ m{\At/};
    return 'producer' if index( $p, $SON ) == 0;
    for (@CORE) { return 'core' if index( $p, "$_/" ) == 0 }
    for (@SITE) { return 'site' if index( $p, "$_/" ) == 0 }
    return 'other-chalk' if $p =~ m{/lib/Chalk/};
    return 'other';
}

sub mod_name ($k) { my $n = $k; return $n unless $n =~ s/\.pm\z//; $n =~ s{/}{::}g; $n }

my %size;    # path -> [bytes, lines]
sub size_of ($p) {
    return $size{$p} //= do {
        my ( $b, $l ) = ( '', '' );
        if ( -f $p && open my $fh, '<:raw', $p ) {
            local $/;
            my $s = <$fh> // '';
            $b = length $s;
            $l = ( $s =~ tr/\n// ) + ( length($s) && substr( $s, -1 ) ne "\n" ? 1 : 0 );
        }
        [ $b, $l ];
    };
}

my %line_text;
sub line_of ( $p, $n ) {
    return '' unless -f $p && $n =~ /\A\d+\z/;
    my $k = "$p:$n";
    return $line_text{$k} //= do {
        open my $fh, '<', $p or return '';
        my $t = '';
        while (<$fh>) { if ( $. == $n ) { $t = $_; last } }
        $t =~ s/\s+\z//; $t =~ s/\A\s+//; $t =~ s/\t/ /g;
        $t;
    };
}

my @metas = sort glob("$R/*.meta");
open my $D, '>', $OD or die;
open my $S, '>', $OS or die;
say $D join "\t", qw(test module inc_key path bytes lines class loc xs pragma phase required_from via_test_line via_module under_test);
say $S join "\t", qw(test exit secs tap_ok tap_not_ok plan init_seen end_seen
  modules modules_compile modules_runtime_only lines lines_compile
  chalk_modules chalk_lines chalk_modules_compile chalk_lines_compile
  harness_modules harness_lines core_modules core_lines site_modules xs_modules producer_modules
  nonpragma_modules nonpragma_lines artifact_modules artifact_lines);

my ( %subtree, %subtree_any, %core_count, %gateway, %immed, %artifact, %closure_size, $ntests_data, %testmods );
for my $mf (@metas) {
    open my $mh, '<', $mf or next;
    my $meta = <$mh> // next;
    chomp $meta;
    my ( $test, $exit, $secs, $nok, $nnot, $plan ) = split /\t/, $meta, 6;
    ( my $inc = $mf ) =~ s/\.meta\z/.inc/;
    my ( %init, %end, %dl, @edges, %first, $init_done, $end_done );
    if ( open my $ih, '<', $inc ) {
        while (<$ih>) {
            chomp;
            my @f = split /\t/;
            if    ( $f[0] eq 'INIT' )      { $init{ $f[1] } = norm_path( $f[2] ) }
            elsif ( $f[0] eq 'END' )       { $end{ $f[1] }  = norm_path( $f[2] ) }
            elsif ( $f[0] =~ /_DL\z/ )     { $dl{ $f[1] } = 1 }
            elsif ( $f[0] eq 'INIT_DONE' ) { $init_done = 1 }
            elsif ( $f[0] eq 'END_DONE' )  { $end_done = 1 }
            elsif ( $f[0] eq 'R' || $f[0] eq 'E' ) {
                my ( $kind, $name, $file, $line, $phase ) = @f;
                $file = norm_path($file);
                push @edges, [ $kind, $name, $file, $line, $phase ];
                $first{$name} //= [ $file, $line, $phase ] if $kind eq 'R';
            }
        }
    }
    my %all = ( %init, %end );    # END wins on path; same anyway
    my %path2key = reverse %all;
    $ntests_data++ if %all;

    # gateway: walk first-load edges up to the test file itself
    my %gw;
    my $gw_of;
    $gw_of = sub ( $k, $depth = 0 ) {
        return $gw{$k} if exists $gw{$k};
        my $fr = $first{$k} or return $gw{$k} = [ '?', '' ];
        my ( $file, $line ) = @$fr;
        if ( $file eq $test ) { return $gw{$k} = [ "$test:$line", $k ] }
        my $pk = $path2key{$file};
        return $gw{$k} = [ $file =~ /\A\(eval/ ? '(string eval)' : "?$file", '' ] unless defined $pk && $depth < 200;
        my $up = $gw_of->( $pk, $depth + 1 );
        return $gw{$k} = $up;
    };

    # first-load tree: how many modules each module's own load brought in (itself included)
    {
        my %kids;
        for my $k ( keys %all ) {
            my $fr = $first{$k} or next;
            my $pk = $path2key{ $fr->[0] } // next;
            push $kids{$pk}->@*, $k unless $pk eq $k;
        }
        my %seen_sz;
        my $sz;
        $sz = sub ($k) {
            return $seen_sz{$k} if $seen_sz{$k};
            $seen_sz{$k} = [ 1, 0, 0 ];    # cycle guard
            my ( $n, $c, $cl ) = ( 1, 0, 0 );
            if ( loc_class( $all{$k} ) eq 'chalk' ) { $c = 1; $cl = size_of( $all{$k} )->[1] || 0 }
            for my $ch ( ( $kids{$k} // [] )->@* ) { my $s = $sz->($ch); $n += $s->[0]; $c += $s->[1]; $cl += $s->[2] }
            return $seen_sz{$k} = [ $n, $c, $cl ];
        };
        for my $k ( keys %all ) {
            my $fr = $first{$k} or next;
            next unless $fr->[0] eq $test;
            my $s = $sz->($k);
            push $subtree{ mod_name($k) }->@*, $s;
        }
        for my $k ( keys %all ) { push $subtree_any{ mod_name($k) }->@*, $sz->($k) }
    }

    # under-test closure: chalk lib modules and everything any of them requires (any edge)
    my %under;
    $under{$_} = 1 for grep { loc_class( $all{$_} ) eq 'chalk' } keys %all;
    my %req_by;    # requirer key -> [required keys]
    for my $e (@edges) {
        my $rk = $path2key{ $e->[2] } // next;
        push $req_by{$rk}->@*, $e->[1];
    }
    my @q = keys %under;
    while ( defined( my $k = shift @q ) ) {
        for my $c ( ( $req_by{$k} // [] )->@* ) { next if $under{$c}++; push @q, $c }
    }
    # requirers we cannot attribute (string evals) -> not called artifacts (conservative)
    my %unattrib;
    for my $e (@edges) { $unattrib{ $e->[1] } = 1 if !defined $path2key{ $e->[2] } && $e->[2] ne $test }
    # ... and what those modules load in turn
    {
        my @uq = grep { !$under{$_} } keys %unattrib;
        while ( defined( my $k = shift @uq ) ) {
            for my $c ( ( $req_by{$k} // [] )->@* ) { next if $under{$c} || $unattrib{$c}++; push @uq, $c }
        }
    }

    my %t = map { $_ => 0 } qw(modules modules_compile modules_runtime_only lines lines_compile
      chalk_modules chalk_lines chalk_modules_compile chalk_lines_compile harness_modules harness_lines
      core_modules core_lines site_modules xs_modules producer_modules nonpragma_modules nonpragma_lines
      artifact_modules artifact_lines);
    for my $k ( sort keys %all ) {
        my $p   = $all{$k};
        my $loc = loc_class($p);
        my $mn  = mod_name($k);
        my $xs  = $dl{$mn} ? 1 : 0;
        my $class = $xs ? 'xs' : $loc;
        my $pragma = ( $k =~ m{\A[a-z]} && $k =~ /\.pm\z/ ) ? 1 : 0;
        my ( $b, $l ) = size_of($p)->@*;
        my $phase = !$init_done ? 'unknown' : exists $init{$k} ? 'compile' : 'run';
        my $fr = $first{$k};
        my $rf = $fr ? "$fr->[0]:$fr->[1]" : '';
        my ( $gwl, $gwm ) = $gw_of->($k)->@*;
        my $gwtext = $gwl =~ /\A\Q$test\E:(\d+)\z/ ? line_of( $test, $1 ) : $gwl;
        my $ut = $under{$k} ? 'yes' : $unattrib{$k} ? 'unknown' : 'no';
        say $D join "\t", $test, $mn, $k, $p, $b, $l, $class, $loc, $xs, $pragma, $phase, $rf,
          ( $gwl =~ /\A\Q$test\E:(\d+)\z/ ? "$1: $gwtext" : $gwtext ), ( $gwm ? mod_name($gwm) : "" ), $ut;
        my $ln = $l || 0;
        $t{modules}++; $t{lines} += $ln;
        if ( $phase eq 'compile' ) { $t{modules_compile}++; $t{lines_compile} += $ln } elsif ( $phase eq 'run' ) { $t{modules_runtime_only}++ }
        if ( $loc eq 'chalk' ) {
            $t{chalk_modules}++; $t{chalk_lines} += $ln;
            if ( $phase eq 'compile' ) { $t{chalk_modules_compile}++; $t{chalk_lines_compile} += $ln }
        }
        if ( $loc eq 'harness' ) { $t{harness_modules}++; $t{harness_lines} += $ln }
        if ( $loc eq 'core' )    { $t{core_modules}++; $t{core_lines} += $ln }
        $t{site_modules}++     if $loc eq 'site';
        $t{xs_modules}++       if $xs;
        $t{producer_modules}++ if $loc eq 'producer';
        unless ($pragma) { $t{nonpragma_modules}++; $t{nonpragma_lines} += $ln }
        if ( $ut eq 'no' ) {
            $t{artifact_modules}++; $t{artifact_lines} += $ln;
            my $ar = $artifact{$mn} //= { tests => 0, lines => $ln, loc => $loc, xs => $xs, gw => {}, rf => {} };
            $ar->{tests}++;
            $ar->{gw}{ $gwm ? mod_name($gwm) . " [$gwtext]" : $gwtext }++;
            $ar->{rf}{$rf}++;
        }
        $core_count{$mn}++;
        $gateway{$mn}{ $gwm ? mod_name($gwm) . "  [$gwtext]" : $gwtext }++; 0 and $gateway{$mn}{ $gwm ? "$gwm  [$gwtext]" : $gwtext }++;
        $immed{$mn}{$rf}++;
        $testmods{$test}{$mn} = 1;
    }
    say $S join "\t", $test, $exit, $secs, $nok, $nnot, $plan, ( $init_done ? 1 : 0 ), ( $end_done ? 1 : 0 ),
      map { $t{$_} } qw(modules modules_compile modules_runtime_only lines lines_compile
      chalk_modules chalk_lines chalk_modules_compile chalk_lines_compile harness_modules harness_lines
      core_modules core_lines site_modules xs_modules producer_modules nonpragma_modules nonpragma_lines
      artifact_modules artifact_lines);
}
close $D; close $S;

# report
open my $O, '>', $OR or die;
my $N = $ntests_data;
say $O "tests with data: $N of " . scalar(@metas);
say $O "\n== modules by number of tests loading them (>= 50%)";
for my $m ( sort { $core_count{$b} <=> $core_count{$a} || $a cmp $b } keys %core_count ) {
    my $c = $core_count{$m};
    last if $c < $N * 0.5;
    my ($g)  = sort { $gateway{$m}{$b} <=> $gateway{$m}{$a} } keys $gateway{$m}->%*;
    my ($im) = sort { $immed{$m}{$b} <=> $immed{$m}{$a} } keys $immed{$m}->%*;
    printf $O "%4d %5.1f%%  %-55s first-required-from %-50s gateway(%d) %s\n", $c, 100 * $c / $N, $m, $im,
      $gateway{$m}{$g}, $g;
}
say $O "\n== artifacts (loaded, not reached from any chalk lib module), by tests";
for my $m ( sort { $artifact{$b}{tests} <=> $artifact{$a}{tests} || $a cmp $b } keys %artifact ) {
    my $ar = $artifact{$m};
    my @g = sort { $ar->{gw}{$b} <=> $ar->{gw}{$a} } keys $ar->{gw}->%*;
    printf $O "%4d  %-45s %-8s lines=%-6s via: %s\n", $ar->{tests}, $m, $ar->{loc}, $ar->{lines},
      join( ' | ', map {"$_ ($ar->{gw}{$_})"} @g[ 0 .. ( $#g < 2 ? $#g : 2 ) ] );
}

sub med (@x) { @x = sort { $a <=> $b } @x; return @x ? $x[ int( $#x / 2 ) ] : 0 }
say $O "\n== use lines in test files: modules each one's load brings in (median over tests; total, chalk, chalk lines)";
for my $m ( sort { scalar( $subtree{$b}->@* ) <=> scalar( $subtree{$a}->@* ) || $a cmp $b } keys %subtree ) {
    my @s = $subtree{$m}->@*;
    next if @s < 5;
    printf $O "%4d tests  %-50s median %4d modules, %4d chalk, %6d chalk lines; max %d\n", scalar @s, $m,
      med( map { $_->[0] } @s ), med( map { $_->[1] } @s ), med( map { $_->[2] } @s ), max( map { $_->[0] } @s );
}
say $O "\n== any module: modules its own load brings in (median, top 40 by median, seen in >= 20 tests)";
my @big = grep { $subtree_any{$_}->@* >= 20 } keys %subtree_any;
for my $m ( ( sort { med( map { $_->[0] } $subtree_any{$b}->@* ) <=> med( map { $_->[0] } $subtree_any{$a}->@* ) } @big )[ 0 .. 39 ] ) {
    my @s = $subtree_any{$m}->@*;
    printf $O "%4d tests  %-50s median %4d modules, %4d chalk, %6d chalk lines\n", scalar @s, $m,
      med( map { $_->[0] } @s ), med( map { $_->[1] } @s ), med( map { $_->[2] } @s );
}
