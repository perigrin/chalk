our %h = (a=>1); sub f { local $h{a} = $h{a} + 1; $_[0] ? f($_[0]-1) : $h{a} } print f(2), $h{a}, "\n";
