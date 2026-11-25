sub depth { my $n = shift; $n == 0 ? 0 : 1 + depth($n-1) } print depth(5000), "\n";
