package T; sub DESTROY { $main::n++ } package main; our $n = 0; for (1..3) { my $o = bless {}, "T"; } print "$n\n";
