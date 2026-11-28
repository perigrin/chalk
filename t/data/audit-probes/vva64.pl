our $x = 1; my @l = sort { local $x = 0; $a <=> $b } 3,1,2; print "@l$x\n";
