our @a = (1,2); sub cnt { scalar @a } sub t { local @a = (1,2,3); cnt() } print t(), cnt(), "\n";
