my $n = 0; sub t { $n++; 1 } sub f { $n += 10; 0 } t() || f(); f() && t(); t() && f(); f() || t(); print "$n\n";
