package P; our $n=0; sub inc { $n++ } package main; my $m="inc"; my $s=""; for (1..3) { P->$m; $s.=$P::n } print "$s\n";
