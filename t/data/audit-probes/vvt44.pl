my @a = (1,2,3); sub f { $a[0]++; "$_[0]" } my $t = ""; for my $x (@a) { $t .= f($x) } print "$t\n";
