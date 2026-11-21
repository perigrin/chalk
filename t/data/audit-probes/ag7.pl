our $g = 0; sub f { $g = $_[0] + 1; $_[0] } my ($a, $b, $c, $d) = (f(1), $g, f(0), $g); print "$a$b$c$d\n";
