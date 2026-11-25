our $g=1; sub f { $g = 7; "$_[0] $_[1]" } print f($g, $g++), "\n";
