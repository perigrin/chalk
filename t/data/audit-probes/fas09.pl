our $x=1; sub f { local $x=$x+1; return $x<4 ? f() : $x } print f(), $x, "\n";
