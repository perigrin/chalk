our @a = (1,2,3); sub f { $a[0]++; $_ } my $t = ""; for (@a) { $t .= f() } print "$t\n";
