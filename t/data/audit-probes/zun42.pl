our $g=1; sub f { local $g=$g+1; return $g if $_[0]==0; f($_[0]-1) } print f(3), $g, "\n";
