use feature 'state'; my @c = map { sub { state $n = 10; $n++ } } 1..2; $c[0]->(); print $c[0]->(), $c[1]->(), "\n";
