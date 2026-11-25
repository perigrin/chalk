our %h=(a=>1); sub g1 { exists $h{b} ? "y$h{b}" : "n" } sub t { local $h{b} = 5; g1() } print t(), g1(), scalar(keys %h), "\n";
