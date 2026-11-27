my %h = (a=>1); sub rh { $h{a} } sub f { local $h{a} = 5; rh() } print f(), rh(), "\n";
