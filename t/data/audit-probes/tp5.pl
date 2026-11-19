our $depth = 0; sub walk { my $n = shift; $depth++; walk($n - 1) if $n > 0; return } for my $k (1..2) { $depth = $depth + 0; walk($k) } print "$depth\n";
