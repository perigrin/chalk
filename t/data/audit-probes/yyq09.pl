my @c = caller(0); sub w { my @c = caller(0); $c[3] } print scalar(@c), w(), "\n";
