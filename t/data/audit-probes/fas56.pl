my %o=(x=>1); sub n { $o{x}=7; 1 } sub two { "$_[0]$_[1]" } print two($o{x}, n()), "\n";
