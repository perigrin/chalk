sub fact { my $n = shift; return 1 if $n <= 1; return $n * fact($n - 1) } print fact(10), "\n";
