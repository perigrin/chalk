sub fact { my $n = shift; return $n <= 1 ? 1 : $n * fact($n - 1) } print fact(5), "\n";
