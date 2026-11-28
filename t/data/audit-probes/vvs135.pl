sub f { return } sub cnt { scalar @_ } print cnt(f(), 1, f()), "\n";
