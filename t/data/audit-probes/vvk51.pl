$_ = 5; sub f { my @l = map { $_ } 1..2; $_ } print f(), "\n";
