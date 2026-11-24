our $n=3; sub more { return $n-- > 0 } my $c=0; while (more()) { $c++ } print "$c $n\n";
