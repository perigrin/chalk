our %h = (a=>1); sub f { local $h{a}; g() } sub g { defined $h{a} ? "d" : "u" } print f(), g(), "\n";
