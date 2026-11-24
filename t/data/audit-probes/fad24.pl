our $g="a"; sub f { local $g=$g."b"; g2() } sub g2 { local $g=$g."c"; die $g."\n" } eval { f() }; print "$g $@";
