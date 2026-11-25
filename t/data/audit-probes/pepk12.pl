our $x=1; sub g { $x } sub f { my $s = ""; for my $i (1..2) { local $x = $x + $i; $s .= g() } $s . $x } print f(), $x, "\n";
