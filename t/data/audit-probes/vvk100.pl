my ($x, $y); $x ||= 5; $x &&= $x + 1; $y //= $x; $y ||= 0; print "$x$y\n";
