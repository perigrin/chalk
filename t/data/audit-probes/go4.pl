sub f { my $n = shift; goto BIG if $n > 5; return "small"; BIG: return "big" } print f(1), f(9), "\n";
