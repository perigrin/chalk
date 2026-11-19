our $s = 1; sub ap { $s += $_[0] } $s += 1; ap(1); $s *= 5; ap(1); print "$s\n";
