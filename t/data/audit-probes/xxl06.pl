our $g = 5; sub dec { $g-- } my $n = 0; until ($g <= 0) { dec(); $n++ } print "$n$g\n";
