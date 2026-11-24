use feature 'state'; sub c { state $n=0; return ++$n } c(); c(); print c(),"\n";
