our $x = 1; sub c { $x = 3; 2 } package O; sub m { "$_[1]$_[2]" } package main; print O->m($x, c()), "\n";
