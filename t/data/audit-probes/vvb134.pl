my $s = ""; my $i = 0; while ($i++ < 3) { my ($x, $y); $s .= defined $y ? "d" : "u"; $y = $i; f($y) } sub f { } print "$s\n";
