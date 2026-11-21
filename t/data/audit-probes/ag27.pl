our $g = 0; sub f { $g = $_[0] + 1; $_[0] } sub k { if ($_[0]) { return (f(1), $g, f(0), $g) } 5 } my @a = k(1); print "@a\n";
