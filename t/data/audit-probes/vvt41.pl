my @a = (1,2,3); sub f { my $v = shift; $a[0]++; $v } my $t = ""; for my $x (@a) { $t .= f($x) . $x } print "$t\n";
