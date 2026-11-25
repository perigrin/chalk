use feature 'state'; sub c { state $n = shift; $n } print c(1), c(2), "\n";
