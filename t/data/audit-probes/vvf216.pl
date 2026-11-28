our $t = "a"; sub c { $t = "zz"; 2 } my @l = (substr($t, 0, 1), c()); print "@l\n";
