sub f { return reverse "abc" } sub g { scalar reverse "abc" } print f(), g(), scalar(f()), "\n";
