our $x = 1; sub c { $x = 3; 2 } sub cpy { my $v = shift; $v } my @l = (cpy($x), c()); print "@l\n";
