my @a = (1,2,3); sub f { $_[0] + $a[2] } my $t = 0; for my $x (@a) { $x++; $t += f($x) } print "$t\n";
