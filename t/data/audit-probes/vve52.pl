my $x = 1; sub f { undef $_[0]; defined $_[0] ? "d" : "u" } print f($x), defined $x ? "d" : "u", "\n";
