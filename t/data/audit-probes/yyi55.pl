sub f { my %o = (size => 1, name => "d", @_); "$o{size}$o{name}" } print f(), f(name => "n"), f(size => 2, name => "x", size => 3), "\n";
