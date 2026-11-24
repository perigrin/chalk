our @x=(1); sub n { $x[0]=7; 1 } sub two { "$_[0]$_[1]" } print two($x[0], n()), "\n";
