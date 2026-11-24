our $x=1; sub n { $x=7; 1 } sub two { "$_[0]$_[1]" } print two($x, n()), two(n(), $x), "\n";
