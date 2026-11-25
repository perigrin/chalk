my @s = sort { $a <=> $b } map { $_ * 7 % 11 } 1..10; print "@s\n";
