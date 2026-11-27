our %g = (a=>1,b=>2); sub rk { "$g{a}$g{b}" } sub f { local @g{qw(a b)} = (8,9); rk() } print f(), rk(), "\n";
