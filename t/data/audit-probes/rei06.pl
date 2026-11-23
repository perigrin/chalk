our $n=0; sub bump { $n++ } my $c=0; while ($n<3) { bump(); $c++ } print "$c\n";
