my ($x,$y) = (1,2); undef $x, $y = 3; print defined $x ? "d" : "u", "$y\n";
