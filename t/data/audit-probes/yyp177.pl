my $x="ab"; sub f { "@_" } print f($x, $x =~ tr/a/z/), "\n";
