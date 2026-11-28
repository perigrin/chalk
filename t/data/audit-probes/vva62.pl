our $x = 1; my @l = map { local $x = $_; $x * 2 } 1..3; print "@l$x\n";
