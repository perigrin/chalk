package P; our $n=0; sub inc { $n++ } package main; my $s=""; for (1..3) { P::inc(); $s.=$P::n } print "$s\n";
