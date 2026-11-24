sub f { my $y=1; g($y); $y } sub g { $_[0] .= "!"; 0 } print f(),"\n";
