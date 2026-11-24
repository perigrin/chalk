use feature 'state'; sub c { state @a; push @a, shift; scalar @a } c(1); print c(2),"\n";
