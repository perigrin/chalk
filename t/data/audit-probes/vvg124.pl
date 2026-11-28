use feature 'state'; sub nx { state $n = 0; ++$n } nx(); nx(); print nx(), "\n";
