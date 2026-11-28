my $x = "a"; sub f { "@_" } print f($x, $x .= "b", $x), "\n";
