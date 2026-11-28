my $x = 1; sub f { $x = 5; scalar(@_) . $_[-1] } print f(0, $x), "\n";
