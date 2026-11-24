my @a=(1); sub cl { @a=() } my $n=0; while (@a) { cl(); $n++ } print "$n\n";
