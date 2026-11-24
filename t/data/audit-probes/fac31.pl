our %g=(a=>1); sub f { local %g=%g; $g{a}=2; $g{a} } print f(), $g{a}, "\n";
