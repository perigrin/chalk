our %x = (k=>1); sub c { delete $x{k}; 2 } my @l = ((exists $x{k} ? "e" : "n"), c(), (defined $x{k} ? "d" : "u")); print "@l\n";
