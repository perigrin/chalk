my $g = 0; sub f { $g = $_[0] + 1; $_[0] } sub k { return (f(1), $g, f(0), $g) } my @a = k(); print "@a\n";
