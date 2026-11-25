sub f { $_[0]{k} = 1; $_[1][2] = 1 } my ($h,$a1); f($h,$a1); print ref($h), ref($a1), scalar(@$a1), "\n";
