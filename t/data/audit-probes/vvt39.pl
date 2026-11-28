my @a = (1,2,3); sub f { $a[2] = 10; $_[0] } my $t = 0; for my $x (@a) { $t += f($x) } print "$t\n";
