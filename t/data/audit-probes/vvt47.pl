our @a = (1,2,3); sub f { $a[0]++; $_[0] } my $t = ""; for (@a) { $t .= f($_) } print "$t\n";
