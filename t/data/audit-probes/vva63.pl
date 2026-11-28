our $x = 1; my @l = grep { local $x = $_; $x > 1 } 1..3; print "@l$x\n";
