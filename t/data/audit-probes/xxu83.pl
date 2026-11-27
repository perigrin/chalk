our $x = "ab"; sub c { $x = "cd"; 1 } my @l = (substr($x, 0, 1), c()); print "@l\n";
