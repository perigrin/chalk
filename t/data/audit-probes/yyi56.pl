sub f { my ($s, %o) = @_; join ",", $s, map { "$_=$o{$_}" } sort keys %o } sub g { f("g", @_, z => 1) } print g(a => 2), "|", g(), "\n";
