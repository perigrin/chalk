my $r=[1]; sub f { "@_" } print f($r->[0], $r->[0]++), "\n";
