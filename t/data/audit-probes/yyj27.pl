use feature 'state'; my @c = map { sub { state $n = 0; ++$n } } 1..2; print $c[0]->(), $c[0]->(), $c[1]->(), "\n";
