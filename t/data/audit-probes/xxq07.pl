my $x = 5; my $y = undef($x) // "U"; print "$y", defined $x ? "d" : "u", "\n";
