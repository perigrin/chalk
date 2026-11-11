#!/usr/bin/env perl
# ABOUTME: Census of every regex perl compiles in chalk's files: each regex op's
# ABOUTME: flags and pattern features (or that it is built at run time), as rows or a table.
#
#   script/regex-census.pl --rows FILE...   one row per regex:
#       FILE  LINE  OP  FLAGS  FEATURES(;)  PATTERN
#   script/regex-census.pl [DIR...]         a table per DIR (default lib t):
#       how many regexes, and in how many files, use each feature
#
# It reads what perl compiled (B::RegexCensus, a B backend), not the source
# text: escapes, classes and \Q..\E are perl's own reading. A file is compiled
# with -c (its BEGIN blocks run; its main line does not). Run from chalk's root.
use v5.36;
use File::Find;
use FindBin;

my $rows = @ARGV && $ARGV[0] eq '--rows' ? shift : 0;
my $jobs = 4;

sub census_of ($file) {
    my $out = qx($^X -I$FindBin::Bin/lib -Ilib -It/lib -MO=-q,RegexCensus $file 2>/dev/null);
    return ( $? == 0 ? 'ok' : 'failed to compile', grep { /\t/ } split /\n/, $out );
}

if ($rows) {
    for my $f (@ARGV) { my ( undef, @r ) = census_of($f); say for @r }
    exit 0;
}

my @dirs = @ARGV ? @ARGV : qw(lib t);
for my $dir (@dirs) {
    my @files;
    find( { no_chdir => 1, wanted => sub { push @files, $_ if -f && /\.(?:pm|pl|t)\z/ } }, $dir );
    @files = sort @files;
    # (in $jobs children: compiling chalk's tests loads chalk each time)
    my ( @kids, @rows, @failed );
    for my $j ( 0 .. $jobs - 1 ) {
        pipe my $r, my $w or die $!;
        my $pid = fork // die $!;
        if ( !$pid ) {
            close $r;
            for my $i ( grep { $_ % $jobs == $j } 0 .. $#files ) {
                my ( $st, @r ) = census_of( $files[$i] );
                print {$w} "FAILED\t$files[$i]\n" if $st ne 'ok';
                print {$w} "$_\n" for @r;
            }
            exit 0;
        }
        close $w;
        push @kids, [ $pid, $r ];
    }
    for my $k (@kids) {
        my $fh = $k->[1];
        while (<$fh>) { chomp; /\AFAILED\t(.*)/ ? push @failed, $1 : push @rows, $_ }
        waitpid $k->[0], 0;
    }
    my ( %n, %in, %ops );
    for (@rows) {
        my ( $file, undef, $op, $flags, $feat ) = split /\t/;
        $ops{$op}++;
        for my $f ( ( map {"flag /$_"} split / /, $flags ), split /;/, $feat ) { $n{$f}++; $in{$f}{$file} = 1 }
    }
    say "== $dir: " . scalar(@files) . " files, " . scalar(@rows) . " regexes ("
      . join( ', ', map {"$_ $ops{$_}"} sort keys %ops ) . ")"
      . ( @failed ? "; " . scalar(@failed) . " did not compile: @failed" : '' );
    printf "%6d  %4d files  %s\n", $n{$_}, scalar keys %{ $in{$_} }, $_ for sort { $n{$b} <=> $n{$a} || $a cmp $b } keys %n;
}
