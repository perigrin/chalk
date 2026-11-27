our $x = "ab"; sub c { $x = "cd"; 1 } my @l = ($x =~ /a/ ? "m" : "n", c(), $x =~ /a/ ? "m" : "n"); print "@l\n";
