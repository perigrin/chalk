our %h=(a=>1); sub f { local $h{a}=2; g() } sub g { $h{a} } print f(), $h{a}, "\n";
