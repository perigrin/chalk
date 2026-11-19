our $i = 0; sub nx { $i++ } my $n = 0; while ($i < 3) { nx(); $n++; last if $n > 10 } print "$n $i\n";
