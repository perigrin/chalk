our $c = 0; my @s = sort { $c++; $a <=> $b } 3,1,2; print "@s ", ($c > 0 ? "y":"n"), "\n";
