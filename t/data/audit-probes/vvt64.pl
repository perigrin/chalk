my @a = (1,2,3); sub f { $_[0] .= "a" } my $t = ""; for my $x (@a) { my $y; f($y) for 1..$x; $t .= "$y," } print "$t\n";
