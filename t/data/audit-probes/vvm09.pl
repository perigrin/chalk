our %h = (a=>1); sub f { local %h; $h{z} = 1; g() } sub g { join(",", sort keys %h) } print f(), g(), "\n";
