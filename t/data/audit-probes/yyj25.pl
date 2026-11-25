use feature 'state'; sub c { state $n = 0; ++$n } print c(), c(), c(), "\n";
