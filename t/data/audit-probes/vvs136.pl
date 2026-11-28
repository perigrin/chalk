sub f { return } my ($x, $y) = (f(), 1); print defined $x ? $x : "u", defined $y ? $y : "u", "\n";
