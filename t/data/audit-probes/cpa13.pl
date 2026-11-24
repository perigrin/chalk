our %g=(a=>1); sub f { my %c=%g; $c{a}=2; $g{a}=3; return $c{a} } print f(), " $g{a}\n";
