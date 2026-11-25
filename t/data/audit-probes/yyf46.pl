my @a=("abc","def"); for my $x (@a) { substr($x, 0, 1, "Z") } print "@a\n";
