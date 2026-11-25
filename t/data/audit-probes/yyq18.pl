our @a=(1,2); sub n { scalar @a } sub t { local @a; n() } print t(), n(), "\n";
