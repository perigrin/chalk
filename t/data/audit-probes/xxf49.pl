our $g = 1; sub rd { $g } my @s = sort { local $g = 9; $a <=> $b } 2,1; print "@s", rd(), "\n";
