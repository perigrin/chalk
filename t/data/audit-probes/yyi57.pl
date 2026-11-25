sub f { scalar(@_) . (defined $_[0] ? "d" : "u") } my @e; my %h; print f(), f(undef), f(@e), f(@e, 1), f(%h), f(()), f((), ()), f(my @x = ()), "\n";
