my @a=("abc","def"); for my $x (@a) { substr($x, 1, 1) = "-" } print "@a\n";
