package P; our $n=0; sub inc { $n++ } package main; my $f=\&P::inc; my $s=""; for (1..3) { $f->(); $s.=$P::n } print "$s\n";
