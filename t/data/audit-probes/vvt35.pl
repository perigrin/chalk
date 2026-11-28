package O; sub f { $_[1] .= "x" } package main; my @a = (1,2,3); O->f($_) for @a; print "@a\n";
