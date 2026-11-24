our $n=3; sub dec { $n-- } my $c=0; while ($n>0) { dec(); $c++ } print "$c $n\n";
