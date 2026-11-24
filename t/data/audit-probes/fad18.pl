our $g=1; sub f { for (1..3) { local $g=$_; return $g if $_==2 } 0 } print f(), $g, "\n";
