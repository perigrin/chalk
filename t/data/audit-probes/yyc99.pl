my $x="a"; sub f { $x .= "f"; "F" } sub g { $x .= "g"; "G" } $x = f() . $x . g(); print "$x\n";
