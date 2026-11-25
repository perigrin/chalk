our $g=0; sub f { for (1..3) { local $g=$_; return $g if $_==2 } 9 } print f(), $g, "\n";
