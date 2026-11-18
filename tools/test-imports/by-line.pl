#!/usr/bin/env perl
# ABOUTME: Group a test-imports.tsv's artifacts (under_test = no) by the line in the
# ABOUTME: test that brings them in: tests with the line, median artifact modules and lines.
#   perl tools/test-imports/by-line.pl test-imports.tsv [MIN_TESTS]
use v5.42;

my ( $file, $min ) = @ARGV;
$min //= 1;
open my $fh, '<', $file or die "$file: $!";
chomp( my $head = <$fh> );
my @h = split /\t/, $head;
my %col; @col{@h} = 0 .. $#h;

my %per;    # line -> test -> [modules, lines]
while (<$fh>) {
    chomp;
    my @f = split /\t/, $_, -1;
    next unless $f[ $col{under_test} ] eq 'no';
    ( my $line = $f[ $col{via_test_line} ] ) =~ s/\A\d+:\s*//;
    $line =~ s/\s+#.*//;
    my $r = $per{$line}{ $f[ $col{test} ] } //= [ 0, 0 ];
    $r->[0]++;
    $r->[1] += $f[ $col{lines} ] || 0;
}
sub median (@v) { @v = sort { $a <=> $b } @v; @v ? $v[ $#v / 2 ] : 0 }
my @rows = map {
    my @t = values $per{$_}->%*;
    [ $_, scalar @t, median( map { $_->[0] } @t ), median( map { $_->[1] } @t ) ]
} keys %per;
say join "\t", qw(line tests artifact_modules artifact_lines);
say join "\t", @$_ for sort { $b->[1] <=> $a->[1] || $a->[0] cmp $b->[0] } grep { $_->[1] >= $min } @rows;
