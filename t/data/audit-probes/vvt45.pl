my @a = (1,2,3); sub f { $a[0]++; return @_ } my $t = ""; for my $x (@a) { $t .= join("", f($x)) } print "$t\n";
