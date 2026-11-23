sub f { my @a = (1,2); for my $i (1..3) { return @a if $i == 2; for (@a) { $_ .= "x" } } return } print join(",", f()), "\n";
